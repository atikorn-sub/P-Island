<div align="center">

<img src="docs/images/icon.png" width="128" alt="ไอคอน P Island">

# P Island

**รอยบากอัจฉริยะสำหรับ MacBook**
เพลง แจ้งเตือน ไฟล์ ปฏิทิน และอีกมากมาย อยู่ตรงรอยบากที่เดียว

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Apple silicon & Intel](https://img.shields.io/badge/Apple%20silicon%20%26%20Intel-universal-555)
![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-orange?logo=swift)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)

[English](README.md) · **ภาษาไทย**

[**⬇︎ ดาวน์โหลดเวอร์ชันล่าสุด**](../../releases/latest)

</div>

---

## ทำอะไรได้บ้าง

เลื่อนเมาส์ไปที่รอยบาก แผงเล็ก ๆ จะกางออกมา ตอนหดอยู่ก็คอยบอกเรื่องสำคัญรอบ ๆ กล้องแบบเงียบ ๆ

| | |
|---|---|
| 🎵 **เพลง** | Apple Music, Spotify และ YouTube Music (Chrome) มีปก ชื่อเพลง แถบเวลาที่ลากได้ ปุ่มเล่น/หยุด/ข้าม ปกพลิกตอนเปลี่ยนเพลง มีโหมดแถบยาวบนแถบเมนู และคลื่นเสียงที่ขยับตามเสียงจริง |
| 🔔 **แจ้งเตือน** | แจ้งเตือนจากแอปอื่นยืดลงมาจากรอยบาก ตอบ iMessage ได้โดยไม่ต้องสลับแอป และเงียบเองตอนเปิดโหมด Focus |
| 📂 **ชั้นวางไฟล์** | ลากไฟล์ไปที่รอยบากเพื่อพักไว้ ส่ง AirDrop ลากออกไปใช้ทีหลัง หรือแปลงไฟล์ เช่น รูป ↔ PNG/JPEG/HEIC/PDF, วิดีโอ → MP4/MOV/M4A, Word/RTF → PDF และถอดเสียงเป็นข้อความ |
| 📅 **ปฏิทินและอากาศ** | ปฏิทินรายเดือน นัดหมายวันนี้ และปุ่ม **เข้าร่วม** ก่อนประชุม Zoom, Meet, Teams, FaceTime หรือ Webex ประมาณ 1 นาที พร้อมสภาพอากาศและพยากรณ์ 3 วัน |
| 📋 **คลิปบอร์ด** | จำ 40 รายการล่าสุดที่คัดลอก ค้นหาได้ เก็บในหน่วยความจำเท่านั้น และข้ามรหัสผ่านจากแอปจัดการรหัสผ่าน |
| ⏱ **ตัวจับเวลา** | มีเวลาตั้งไว้ให้กด นับถอยหลังบนรอยบาก และมีเสียงพร้อมเด้งเตือนตอนครบเวลา |
| 🔋 **ระบบ** | แบตเป็นสีเขียว/ส้ม/แดง เตือนแบตน้อยและชาร์จเต็ม บอกเวลาที่ใช้ได้ แถบปรับเสียงและความสว่างที่รอยบาก แจ้งตอน AirPods เชื่อมต่อพร้อม % แบตแต่ละข้าง |
| 🎨 **ปรับแต่งได้** | หน้าตาแบบดำหรือกระจก (บน macOS 26 เป็น Liquid Glass ของจริง) มี 4 ขนาด เลือกไทยหรืออังกฤษได้ ปุ่มลัด <kbd>⌃⌥I</kbd> และ <kbd>⌃⌥T</kbd> และปัดสลับแถบได้ |

<!--
ภาพหน้าจอ: ใส่ไฟล์ PNG ไว้ใน docs/screenshots/ แล้วเอาเครื่องหมายคอมเมนต์ของส่วนนี้ออก

<p align="center">
  <img src="docs/screenshots/home.png" width="49%"> <img src="docs/screenshots/slim-bar.png" width="49%">
  <img src="docs/screenshots/notification.png" width="49%"> <img src="docs/screenshots/settings.png" width="49%">
</p>
-->

---

## วิธีติดตั้ง

**ต้องมี:** macOS 14 Sonoma ขึ้นไป ใช้ได้กับ Mac ทุกรุ่น (ชิป Apple หรือ Intel) มีรอยบากจะสวยที่สุด แต่ไม่มีก็ใช้ได้

1. **ดาวน์โหลด** ไฟล์ `P-Island-x.y.dmg` จาก[เวอร์ชันล่าสุด](../../releases/latest)
2. **เปิด**ไฟล์ `.dmg` แล้ว**ลาก P Island ไปวางบน Applications**
3. **เปิด P Island** จาก Applications หรือ Launchpad
4. macOS จะแจ้งว่าตรวจสอบผู้พัฒนาไม่ได้ เพราะ P Island ไม่ได้ขายผ่าน Apple วิธีอนุญาต (ทำแค่ครั้งแรกครั้งเดียว)
   - **macOS 15 Sequoia ขึ้นไป:** เปิด **System Settings › Privacy & Security** เลื่อนลงไปที่ *"P Island" was blocked…* กด **Open Anyway** แล้วกด **Open**
   - **macOS 14 Sonoma:** คลิกขวาที่ P Island ใน Applications › **Open** › **Open**

   <details><summary>ยังขึ้นว่าแอป "is damaged" อยู่?</summary>

   เป็นเพราะ macOS ติดป้ายไฟล์ที่ดาวน์โหลดมาจากเน็ตไว้ ให้ลบป้ายนี้ใน Terminal แล้วเปิดแอปอีกครั้ง

   ```bash
   xattr -dr com.apple.quarantine "/Applications/P Island.app"
   ```
   </details>

5. จะมีไอคอนแคปซูลขึ้นบนแถบเมนู และหน้าต่าง**การตั้งค่า**จะเปิดที่หมวด**สิทธิ์การเข้าถึง** ทุกสิทธิ์ด้านล่างไม่บังคับ เลือกให้เฉพาะที่อยากใช้ก็พอ

### สิทธิ์ที่ใช้

| สิทธิ์ | ใช้ทำอะไร | วิธีให้ |
|---|---|---|
| **Full Disk Access** | แจ้งเตือนจากแอปอื่น ตอบ iMessage และรู้ว่าเปิดโหมด Focus อยู่ | กด *เปิดการตั้งค่า* แล้วลาก P Island จากหน้าต่าง Finder ลงในรายการ และเปิดสวิตช์ |
| **Calendar** | นัดหมาย ปฏิทินรายเดือน ปุ่มเข้าประชุม | กด *อนุญาต* |
| **Bluetooth** | แจ้งตอน AirPods และอุปกรณ์อื่นเชื่อมต่อ | กด *อนุญาต* |
| **Automation** (Music, Spotify, Messages) | อ่านและควบคุมเพลง ส่งข้อความตอบกลับ | macOS จะถามตอนใช้ครั้งแรก |
| **Speech Recognition** | ถอดเสียงจากไฟล์เป็นข้อความ | macOS จะถามตอนถอดเสียงครั้งแรก |
| **System Audio Recording** | คลื่นเสียงตามเพลงจริง (ปิดไว้เป็นค่าเริ่มต้น) | macOS จะถามตอนเปิดใช้ |

ดูสถานะของแต่ละสิทธิ์ได้ที่ **การตั้งค่า › สิทธิ์การเข้าถึง** สถานะจะอัปเดตเองทันที ถ้าอยากให้แอปเปิดเองทุกครั้งที่เข้าเครื่อง เปิด **เปิดตอนเข้าเครื่อง** ได้ที่ **การตั้งค่า › ทั่วไป**

### YouTube Music (ไม่บังคับ)

Apple Music กับ Spotify ใช้ได้ทันที ถ้าฟัง YouTube Music ใน Chrome ให้ติดตั้งส่วนขยายเล็ก ๆ เพิ่ม

1. ดาวน์โหลด `P-Island-YouTube-Music-Extension.zip` จาก[เวอร์ชันล่าสุด](../../releases/latest) แล้วแตกไฟล์
2. ใน Chrome ไปที่ `chrome://extensions` แล้วเปิด **Developer mode** (มุมขวาบน)
3. กด **Load unpacked** แล้วเลือกโฟลเดอร์ที่แตกไฟล์ไว้
4. รีเฟรชแท็บ YouTube Music หนึ่งครั้ง

ส่วนขยายนี้ทำงานเฉพาะในหน้า `music.youtube.com` และคุยกับ P Island ในเครื่องคุณเองเท่านั้น (`127.0.0.1`)

---

## วิธีใช้

- **เปิดรอยบาก:** ชี้เมาส์ที่รอยบาก หรือกด <kbd>⌃⌥I</kbd> ส่วน <kbd>⌃⌥T</kbd> ไปที่ตัวจับเวลาเลย
- **แถบต่าง ๆ:** หน้าหลัก · ปฏิทินและสภาพอากาศ · ชั้นวางไฟล์ · คลิปบอร์ด · ตัวจับเวลา คลิกที่ไอคอน หรือปัดซ้าย-ขวาสองนิ้วบนแทร็กแพด
- **ไฟล์:** ลากไฟล์ขึ้นไปที่รอยบากแล้ววางบนชั้นวาง คลิกขวาที่ไฟล์เพื่อส่ง AirDrop แปลงไฟล์ หรือถอดเสียง
- **การตั้งค่า:** กด ⚙️ ในรอยบากที่กางอยู่ หรือไอคอนแคปซูลบนแถบเมนู › การตั้งค่า… (<kbd>⌘,</kbd>)

## ความเป็นส่วนตัว

ข้อมูลทุกอย่างอยู่ในเครื่องคุณ

- แจ้งเตือนและข้อความ**อ่านในเครื่องแบบอ่านอย่างเดียว** ไม่มีการอัปโหลดไปที่ไหน
- ประวัติคลิปบอร์ดเก็บ**ในหน่วยความจำเท่านั้น** หายเมื่อปิดแอป และข้ามข้อมูลที่แอปจัดการรหัสผ่านติดป้ายว่าเป็นความลับ
- ใช้อินเทอร์เน็ตแค่ดึง**สภาพอากาศ** ([Open-Meteo](https://open-meteo.com) ส่งไปแค่พิกัดเมืองที่เลือก) และ**ปกเพลง**จากบริการเพลง
- ตัวเชื่อม YouTube Music รับการเชื่อมต่อแค่ใน**เครื่องตัวเอง (127.0.0.1)** และเฉพาะจาก Chrome extension เท่านั้น

## แก้ปัญหาเบื้องต้น

| ปัญหา | วิธีแก้ |
|---|---|
| แจ้งเตือนไม่ขึ้น | ให้สิทธิ์ **Full Disk Access** (การตั้งค่า › สิทธิ์การเข้าถึง) แล้วปิดและเปิด P Island ใหม่ |
| ไม่เจอเพลงที่เล่น | อนุญาตให้ P Island ควบคุม Music / Spotify ที่ System Settings › Privacy & Security › Automation |
| YouTube Music ไม่ขึ้น | เช็กว่าเปิดส่วนขยายอยู่ แล้วรีเฟรชแท็บ YouTube Music |
| รอยบากบังแถบเมนูบางส่วน | นั่นคือโหมด*แถบยาว* เปลี่ยนเป็น*ปีกเล็ก*ได้ที่ การตั้งค่า › ทั่วไป |

---

## Build เองจากซอร์สโค้ด

ใช้แค่ Command Line Tools ของ Apple ไม่ต้องมีโปรเจกต์ Xcode

```bash
xcode-select --install          # ทำครั้งเดียว
git clone https://github.com/atikorn-sub/P-Island.git
cd P-Island
./build.sh --install            # build แล้วติดตั้งลง /Applications
./build.sh --release            # ได้ .dmg แบบ universal และ .zip ของส่วนขยายใน dist/
```

ถ้าใน Keychain มีใบรับรองชื่อ **P Island Developer** ตัว build จะเซ็นแอปด้วยใบรับรองนั้น (สร้างได้ที่ Keychain Access › Certificate Assistant › Create a Certificate… เลือกประเภท *Code Signing*) จะทำให้สิทธิ์ของ macOS ไม่หายเวลา build ใหม่ ถ้าไม่มี จะเซ็นแบบ ad-hoc แทน

## เบื้องหลังการทำงาน

<details><summary>สำหรับคนที่สนใจ</summary>

- **ตัวรอยบาก** เป็น `NSPanel` แบบไม่มีขอบที่อยู่เหนือแถบเมนู คำนวณขนาดจาก `NSScreen.safeAreaInsets` และ `auxiliaryTopLeftArea/RightArea` ตอนหดจะไม่รับเมาส์ แถบเมนูเลยยังกดได้ตามปกติ และใช้ global event monitor ตรวจว่าเมาส์ชี้อยู่ไหม หน้าจอทำด้วย SwiftUI ใช้ `Shape` รูปรอยบากที่วาดเอง และแอนิเมชันแบบสปริง
- **เพลง:** Apple Music กับ Spotify ผ่าน AppleScript และ distributed notification ส่วน YouTube Music ผ่าน Chrome extension ที่ส่งสถานะเพลงผ่าน WebSocket ในเครื่อง (`Network.framework` รับเฉพาะ loopback และเฉพาะ origin ของ extension)
- **แจ้งเตือน:** อ่านฐานข้อมูล SQLite ของ Notification Center แบบอ่านอย่างเดียว และตอบ iMessage ผ่าน AppleScript ของแอป Messages
- **Focus:** เฝ้าโฟลเดอร์ฐานข้อมูล Focus ของ macOS ด้วย `DispatchSource` และคำนวณโหมด Focus ที่ตั้งเวลาไว้เอง
- **ระบบ:** CoreAudio สำหรับระดับเสียง และ process tap สำหรับคลื่นเสียงจริง, IOKit สำหรับแบตเตอรี่, EventKit, IOBluetooth, Speech, ตัวแปลงไฟล์ด้วย PDFKit/AVFoundation และปุ่มลัดด้วย Carbon
- **กระจก:** ใช้ `glassEffect` ของ SwiftUI บน macOS 26 ส่วนเวอร์ชันก่อนหน้าใช้การเบลอของ `NSVisualEffectView` พร้อมแสงสะท้อนและเส้นขอบ
- **ภาษา:** ทุกข้อความมีทั้งไทยและอังกฤษ วันที่เปลี่ยนตามภาษาที่เลือก (ภาษาไทยใช้ปี พ.ศ.)

```
Sources/           โค้ดแอป Swift (ประมาณ 5,900 บรรทัด 37 ไฟล์)
ChromeExtension/   ส่วนขยายสำหรับ YouTube Music (Manifest V3)
Resources/         Info.plist, ไอคอน, ข้อความขอสิทธิ์สองภาษา
Design/            ไฟล์ต้นฉบับโลโก้
build.sh           สคริปต์ build ติดตั้ง และทำไฟล์สำหรับแจก
```
</details>

## เครดิต

พัฒนาโดย **Atikorn Subsuieng**
ผู้ช่วยเขียนโค้ด: Claude (Anthropic) · ข้อมูลสภาพอากาศจาก [Open-Meteo.com](https://open-meteo.com) (CC BY 4.0) · ได้แรงบันดาลใจจาก Dynamic Island ของ iPhone

## สัญญาอนุญาต

[MIT](LICENSE) © 2026 Atikorn Subsuieng
