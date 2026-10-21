"""Run native scheduling policy assertions using a cached Gradle Kotlin compiler.

Run an Android build once, then: python3 tool/check_reminder_policy.py
Respects JAVA_HOME and GRADLE_USER_HOME; no Android device or downloads needed.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

project = Path(__file__).resolve().parent.parent
gradle = Path(os.environ.get("GRADLE_USER_HOME", str(Path.home() / ".gradle")))
libraries = sorted((gradle / "wrapper/dists").glob("gradle-*/**/lib"))
if not libraries:
    raise SystemExit("Run flutter build apk first to populate the Gradle cache.")
lib = libraries[-1]
stdlib = next(lib.glob("kotlin-stdlib-*.jar"))
annotations = next(lib.glob("annotations-*.jar"))
java_home = os.environ.get("JAVA_HOME")
java = str(Path(java_home) / "bin" / ("java.exe" if os.name == "nt" else "java")) if java_home else shutil.which("java")
if not java:
    raise SystemExit("Set JAVA_HOME or install Java.")
with tempfile.TemporaryDirectory(prefix="recare-policy-") as output:
    subprocess.run([java, "-cp", str(lib / "*"), "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler",
        "-no-stdlib", "-no-reflect", "-classpath", os.pathsep.join([str(stdlib), str(annotations)]),
        "-d", output,
        str(project / "android/app/src/main/kotlin/com/detabev/recare/ReminderPolicy.kt"),
        str(project / "android/app/src/test/kotlin/com/detabev/recare/ReminderPolicyTest.kt")], check=True)
    subprocess.run([java, "-cp", os.pathsep.join([output, str(stdlib)]),
        "com.detabev.recare.ReminderPolicyTestKt"], check=True)
