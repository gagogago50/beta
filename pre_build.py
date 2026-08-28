#!/usr/bin/env python3
"""Build every Android native library locally from pinned source.

No repository-provided .so is trusted. The script builds libtsclient with
Cargo --locked and copies libc++_shared.so from the caller-selected Android NDK.
It then writes SHA-256 hashes for the exact files packaged in the APK.
"""

from __future__ import annotations

import hashlib
import os
import platform
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
NATIVE = ROOT / "native"
JNI_LIBS = ROOT / "android" / "app" / "src" / "main" / "jniLibs"
ANDROID_API = 28
TARGETS = {
    "aarch64-linux-android": ("aarch64-linux-android", "arm64-v8a"),
    "x86_64-linux-android": ("x86_64-linux-android", "x86_64"),
}


def detect_ndk_host() -> str:
    if sys.platform == "win32":
        return "windows-x86_64"
    if sys.platform == "darwin":
        # Current NDK packages expose darwin-x86_64 tools which also run on
        # Apple Silicon through Rosetta.
        return "darwin-x86_64"
    return "linux-aarch64" if platform.machine() == "aarch64" else "linux-x86_64"


def require_ndk() -> tuple[Path, Path]:
    value = os.environ.get("ANDROID_NDK_HOME")
    if not value:
        raise SystemExit("ERROR: ANDROID_NDK_HOME must point to Android NDK 26+.")
    ndk = Path(value).resolve()
    bin_dir = ndk / "toolchains" / "llvm" / "prebuilt" / detect_ndk_host() / "bin"
    if not bin_dir.is_dir():
        raise SystemExit(f"ERROR: invalid NDK toolchain directory: {bin_dir}")
    return ndk, bin_dir


def configure_target_environment(bin_dir: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["PATH"] = str(bin_dir) + os.pathsep + env.get("PATH", "")
    executable = ".cmd" if sys.platform == "win32" else ""
    llvm_ar = bin_dir / ("llvm-ar.exe" if sys.platform == "win32" else "llvm-ar")

    for rust_target, (ndk_triple, _) in TARGETS.items():
        compiler = bin_dir / f"{ndk_triple}{ANDROID_API}-clang{executable}"
        if not compiler.is_file():
            raise SystemExit(f"ERROR: compiler missing for {rust_target}: {compiler}")
        env_key = rust_target.replace("-", "_")
        cargo_key = env_key.upper()
        env[f"CC_{env_key}"] = str(compiler)
        env[f"CXX_{env_key}"] = str(compiler)
        env[f"AR_{env_key}"] = str(llvm_ar)
        env[f"CARGO_TARGET_{cargo_key}_LINKER"] = str(compiler)
    return env


def run(command: list[str], *, cwd: Path, env: dict[str, str]) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=cwd, env=env, check=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def copy_runtime(ndk: Path, host: str, target_triple: str, destination: Path) -> None:
    source = (
        ndk
        / "toolchains"
        / "llvm"
        / "prebuilt"
        / host
        / "sysroot"
        / "usr"
        / "lib"
        / target_triple
        / "libc++_shared.so"
    )
    if not source.is_file():
        raise SystemExit(f"ERROR: trusted NDK C++ runtime not found: {source}")
    shutil.copy2(source, destination / "libc++_shared.so")


def main() -> None:
    ndk, bin_dir = require_ndk()
    host = detect_ndk_host()
    env = configure_target_environment(bin_dir)

    # Ensure target support comes from the locally installed Rust toolchain.
    for target in TARGETS:
        run(["rustup", "target", "add", target], cwd=NATIVE, env=env)

    # Sequential builds use less memory and avoid nondeterministic contention.
    for target in TARGETS:
        run(
            ["cargo", "build", "--locked", "--release", "--target", target],
            cwd=NATIVE,
            env=env,
        )

    hashes: list[str] = []
    for target, (ndk_triple, abi) in TARGETS.items():
        destination = JNI_LIBS / abi
        destination.mkdir(parents=True, exist_ok=True)
        # Remove stale native libraries before copying this build.
        for stale in destination.glob("*.so"):
            stale.unlink()

        engine = NATIVE / "target" / target / "release" / "libtsclient.so"
        if not engine.is_file():
            raise SystemExit(f"ERROR: Cargo output missing: {engine}")
        shutil.copy2(engine, destination / "libtsclient.so")
        copy_runtime(ndk, host, ndk_triple, destination)

        for output in sorted(destination.glob("*.so")):
            relative = output.relative_to(ROOT).as_posix()
            hashes.append(f"{sha256(output)}  {relative}")

    manifest = JNI_LIBS / "native-build.sha256"
    manifest.write_text("\n".join(hashes) + "\n", encoding="utf-8")
    print(f"Native libraries built locally. Hash manifest: {manifest}")


if __name__ == "__main__":
    main()
