"""Adjusts the generated Android project: app name, permissions, and signing.

Runs in CI right after `flutter create`. Fails loudly if Flutter's template
changes so a broken build never ships silently.
"""
import os
import re
import sys

MANIFEST = "android/app/src/main/AndroidManifest.xml"
GRADLE_KTS = "android/app/build.gradle.kts"
GRADLE = "android/app/build.gradle"


def die(msg):
    print(f"patch_android: {msg}", file=sys.stderr)
    sys.exit(1)


m = open(MANIFEST).read()
m = re.sub(r'android:label="[^"]*"', 'android:label="Tool Inventory"', m, count=1)
perms = """
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.INTERNET"/>
"""
if "RECORD_AUDIO" not in m:
    m = m.replace("<application", perms + "    <application", 1)
queries = """
        <intent>
            <action android:name="android.speech.RecognitionService"/>
        </intent>
        <intent>
            <action android:name="android.media.action.IMAGE_CAPTURE"/>
        </intent>
"""
if "RecognitionService" not in m:
    if "<queries>" in m:
        m = m.replace("<queries>", "<queries>" + queries, 1)
    else:
        m = m.replace("</manifest>", "    <queries>" + queries + "    </queries>\n</manifest>", 1)
open(MANIFEST, "w").write(m)
print("manifest patched")

# ML Kit's text plugin references other-language recognizers we don't ship.
rules = """-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
"""
with open("android/app/proguard-rules.pro", "a") as f:
    f.write(rules)
print("proguard rules added")

# Signing: use the permanent key from CI secrets when present.
keystore = os.environ.get("KEYSTORE_PATH")
if keystore and os.path.exists(keystore):
    if not os.path.exists(GRADLE_KTS):
        die("expected build.gradle.kts")
    g = open(GRADLE_KTS).read()
    block = f"""
    signingConfigs {{
        create("release") {{
            storeFile = file("{keystore}")
            storePassword = System.getenv("KEY_PASSWORD")
            keyAlias = "upload"
            keyPassword = System.getenv("KEY_PASSWORD")
        }}
    }}
"""
    if "signingConfigs {" not in g:
        g, n = re.subn(r"(android\s*\{)", r"\1" + block.replace("\\", "\\\\"), g, count=1)
        if n != 1:
            die("could not find android { block")
    g, n = re.subn(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)', 'signingConfig = signingConfigs.getByName("release")', g)
    if n < 1:
        die("could not find release signingConfig line")
    open(GRADLE_KTS, "w").write(g)
    print("release signing configured")
else:
    print("no keystore: release build uses the debug key")
