# ADT কমান্ড রেফারেন্স — প্রতিটা টুল কিভাবে ব্যবহার করবে

প্রতিটা টুলের নিচে: বাংলায় ব্যাখ্যা + ঠিক কোন কমান্ড কী করে। সব কমান্ড `source ~/.bashrc` করার পরে সরাসরি চলবে (PATH-এ থাকে)। কিছু কাজ না করলে আগে `./setup.sh doctor` চালাও — ওটাই বলে দেবে কোন অংশ ভাঙা।

---

## ১. adb — ডিভাইসের সাথে কথা বলার প্রধান টুল

### ডিভাইস কানেক্ট করা

**USB/WiFi-ডিবাগিং দুটোতেই আগে ফোনে ডেভেলপার অপশন চালু করতে হবে:**
Settings → About phone → **Build number**-এ ৭ বার ট্যাপ → তারপর Settings → Additional settings → **Developer options** → **USB debugging** চালু।

**USB দিয়ে (সরাসরি ক্যাবল):**
```bash
adb devices -l          # কানেক্ট করা ডিভাইস দেখাবে; প্রথমবার ফোনে "Allow USB debugging?" আসবে — Allow চাপো
```

**WiFi/ওয়্যারলেস দিয়ে (Android 11+, যেমন Redmi Turbo 4 Pro / Android 16):**

একই WiFi-তে থাকতে হবে। ফোনে: Developer options → **Wireless debugging** চালু → "Pair device with pairing code"-এ ট্যাপ করলে IP:port + ৬ সংখ্যার কোড দেখাবে।

```bash
adb pair 192.168.1.5:37199      # পেয়ারিং স্ক্রিনের IP:port + কোড চাইবে (port বদলায় প্রতিবার)
adb connect 192.168.1.5:5555    # তারপর মূল ওয়্যারলেস আইপি:পোর্টে কানেক্ট (পেয়ারিং port ≠ connect port!)
adb devices -l                  # যাচাই
```
> মনে রাখো: `pair` আর `connect` আলাদা ধাপ, আলাদা পোর্ট ব্যবহার করে — পেয়ারিং পোর্ট দিয়ে connect করলে হবে না।

**ফোন থেকে-ফোনে / একই ডিভাইসে (Termux→নিজের ফোন):** ওয়্যারলেস ডিবাগিং চালু করে উপরের pair/connect একইভাবে।

### প্রতিদিনের adb কাজ

```bash
adb devices -l                          # ডিভাইস তালিকা (model, transport সহ)
adb -s emulator-5554 shell              # একাধিক ডিভাইস থাকলে -s দিয়ে বেছে নিতে হয়
adb shell                               # ফোনের শেলে ঢোকো (exit দিয়ে বের হও)
adb shell getprop ro.product.model      # মডেল পড়ো (যেকোনো prop এভাবে)
adb shell getprop ro.build.version.release   # Android version

adb push file.txt /sdcard/Download/     # PC→ফোন
adb pull /sdcard/Download/file.txt .    # ফোন→PC
adb install app.apk                     # APK ইনস্টল
adb install -r app.apk                  # পুনঃইনস্টল (ডেটা রেখে)
adb uninstall com.example.app           # আনইনস্টল

adb logcat                              # লাইভ লগ (Ctrl+C বন্ধ)
adb logcat -d > log.txt                 # বর্তমান লগ ফাইলে সংরক্ষণ
adb logcat *:E                          # শুধু error লেভেল

adb shell pm list packages | grep name  # ইনস্টলড প্যাকেজ খোঁজো
adb shell screencap /sdcard/s.png && adb pull /sdcard/s.png   # স্ক্রিনশট
adb shell input tap 540 1200            # স্ক্রিনে ট্যাপ সিমুলেট (x y)
adb shell input keyevent KEYCODE_HOME   # বাটন প্রেস

adb reboot                              # রিবুট
adb reboot bootloader                   # fastboot মোডে যাও
adb kill-server && adb start-server     # adb আটকে গেলে রিস্টার্ট
```

**"unauthorized" দেখালে:** ফোনের স্ক্রিন unlock করে Allow দাও; না এলে Developer options → "Revoke USB debugging authorizations" করে আবার চেষ্টা।

---

## ২. fastboot — বুটলোডার লেভেল কাজ (সাবধানে!)

```bash
adb reboot bootloader       # প্রথমে ফোন bootloader মোডে নাও
fastboot devices            # fastboot-এ ডিভাইস দেখা যাচ্ছে কিনা
fastboot flashing unlock    # ⚠️ বুটলোডার আনলক — সব ডেটা মুছে যাবে!
fastboot reboot             # স্বাভাবিক বুটে ফিরো
```
ফ্ল্যাশিং ভুল ইমেজে **ফোন ব্রিক** করতে পারে — যা করছো নিশ্চিত না হলে fastboot-এ কিছু লিখো না।

---

## ৩. aapt2 — APK রিসোর্স টুল (APK বিল্ড/বিশ্লেষণ)

```bash
aapt2 version                          # সংস্করণ
aapt2 dump badging app.apk             # প্যাকেজ নাম, versionCode, minSdk, permissions
aapt2 dump permissions app.apk         # শুধু পারমিশন তালিকা
aapt2 list app.apk                     # APK-র ভেতরের ফাইল তালিকা
```

APK **বিল্ড** পাইপলাইন (রিসোর্স compile → link → zipalign → apksigner সাইন):
```bash
aapt2 compile --dir res/ -o compiled.zip             # রিসোর্স compile
aapt2 link -o app-unsigned.apk -I $ANDROID_HOME/platforms/android-35/android.jar \
    compiled.zip --manifest AndroidManifest.xml -A assets --java gen/    # link + R.java জেনারেট
zipalign -f 4 app-unsigned.apk app-aligned.apk        # 4-বাইট অ্যালাইন (আবশ্যক)
```

Gradle প্রজেক্টে ADT-র aapt2 ব্যবহার করাতে:
```bash
./setup.sh setup-gradle       # gradle.properties-এ android.aapt2FromMavenOverride বসায়
```

---

## ৪. বাকি platform-tools / build-tools

```bash
fastboot, sqlite3, etc1tool, hprof-conv     # platform-tools-এ
aapt dump badging app.apk                   # aapt (legacy) — দ্রুত package info
aidl in.aidl                                # AIDL ইন্টারফেস → Java স্টাব
dexdump classes.dex                         # dex বিশ্লেষণ
split-select                                # APK split বাছাই টুল
```

**APK সাইন করা (JVM টুল, আলাদা ইনস্টল):**
```bash
sudo apt install apksigner
apksigner sign --ks my.keystore app-aligned.apk
apksigner verify --print-certs app.apk
```

---

## ৫. sdkmanager — সরকারি প্যাকেজ ম্যানেজার (Java টুল)

```bash
sdkmanager --list_installed                    # কী কী ইনস্টলড
sdkmanager --list | head -30                   # কী কী পাওয়া যায়
sdkmanager "platforms;android-35"              # প্ল্যাটফর্ম ইনস্টল
sdkmanager "build-tools;35.0.0"                # (মনে রাখো: ARM64-এ ADT-র আর্টিফ্যাক্টই ব্যবহার করো; এরা x86)
sdkmanager --uninstall "platforms;android-34"  # পুরনো প্যাকেজ সরাও (স্টোরেজ বাঁচায়)
yes | sdkmanager --licenses                    # লাইসেন্স অটো-গ্রহণ
```
**ইন্টারনেট লাগে** — একমাত্র এটাই অনলাইন-নির্ভর অংশ।

---

## ৬. NDK / CMake শিম — C/C++ কম্পাইল

ADT-র NDK "শিম" = build system যখন NDK খোঁজে, তখন ডিভাইসের **Termux clang/system টুলে** পাঠিয়ে দেয় (x86 NDK বাইনারি PRoot-এ চলে না — এজন্যেই শিম)।

**সাধারণ C/C++ ফাইল Android-এর জন্য কম্পাইল (ডিভাইসে ভ্যালিডেটেড পদ্ধতি):**
```bash
clang --target=aarch64-linux-android24 hello.c -o hello   # Termux clang দিয়ে native বাইনারি
./hello                                                    # সরাসরি চলে
```

**CMake প্রজেক্ট:** `cmake` আর `ninja` ইনস্টলড থাকে (shim প্রজেক্টের `find_package`-সামঞ্জস্য ঠিক করে দেয়) — সাধারণভাবে `cmake -B build -GNinja && ninja -C build` চলে।

llvm-strip শিম auto-বসে — নিজে কিছু করতে হয় না।

---

## ৭. এনভায়রনমেন্ট / রক্ষণাবেক্ষণ

```bash
echo $ANDROID_HOME                # SDK কোথায় (bootstrap নিজে ~/.bashrc-এ লিখে দেয়)
./setup.sh setup-env              # env ব্লক নষ্ট হলে আবার লিখে দাও
./setup.sh status                 # কী ইনস্টলড, কোন সংস্করণ
./setup.sh doctor                 # সমস্যা ধরো (সব চেক একসাথে)
./setup.sh cleanup                # temp/ডাউনলোড/AOSP ট্রি ক্লিন (স্টোরেজ ফেরত)
./setup.sh list-versions          # কোন কোন সংস্করণ পাওয়া যায়/ইনস্টল করা যায়
```

`ANDROID_HOME` মুছে ফেললে বা নতুন শেলে না এলে: `source ~/.bashrc`।

---

## ৮. সমস্যা → দ্রুত সমাধান টেবিল

| লক্ষণ | সমাধান |
|---|---|
| `adb: command not found` | `source ~/.bashrc`; না হলে `./setup.sh doctor` |
| `unauthorized` | ফোন unlock → Allow; না হলে revoke authorizations |
| `no devices/emulators found` (ওয়্যারলেস) | `adb connect IP:PORT` আবার; দুটো একই WiFi-তে কিনা দেখো |
| sdkmanager-এ Java error | Java নেই — `./setup.sh bootstrap --auto` চালাও (স্বয়ংক্রিয় বসবে) |
| স্টোরেজ ফুল | `./setup.sh cleanup` + `sdkmanager --uninstall` পুরনো platform |
| সব অদ্ভুত আচরণ | `./setup.sh doctor` আউটপুট পড়ো — কোন চেক লাল সেটাই সমস্যা |

---
*পুরো সেটআপ এক লাইনে:* `curl -fsSL https://raw.githubusercontent.com/soobujmiah/adt/main/install.sh | bash`
