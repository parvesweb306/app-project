# Parental Control — Child Device App (Flutter 3.47 compatible)
 
## এবার যা সঠিকভাবে করা হয়েছে
 ![alt text](image.png)
আগের ভার্সনগুলোতে আমি ভুলবশত `android.newDsl=false` ও `android.builtInKotlin=false` লাইন মুছে ফেলেছিলাম — কিন্তু গবেষণা করে নিশ্চিত হয়েছি এগুলো **ভুল ছিল না**, Flutter 3.47-এর official template-এই এই flag গুলো `false` রাখা হয় (কারণ আমাদের `build.gradle` পুরনো "legacy" স্টাইলে লেখা)।

এবার Flutter 3.47-এর **নিশ্চিত ভেরিফায়েড কম্বিনেশন** ব্যবহার করা হয়েছে:
- Android Gradle Plugin (AGP): **9.1.0**
- Gradle: **9.3.1** (AGP 9.1-এর জন্য ন্যূনতম প্রয়োজনীয়)
- Kotlin: **2.4.0**
- `android.newDsl=false`, `android.builtInKotlin=false` (রাখা হয়েছে, মুছা হয়নি)
- `compileSdk`/`targetSdk`: 36
- `minSdk`: 24
- Java compatibility: 17

## ব্যবহারের ধাপ

### ধাপ ১: আগের ফোল্ডার সম্পূর্ণ ডিলিট করো

পুরনো `parental_control_app_fixed` ফোল্ডারটা **সম্পূর্ণ ডিলিট** করে দাও (কোনো ভাঙা cache যেন অবশিষ্ট না থাকে)।

### ধাপ ২: এই নতুন zip extract করো

### ধাপ ৩: `android/local.properties` ঠিক আছে কিনা চেক করো

```
flutter.sdk=E:\flutter
sdk.dir=E:\AndroidSdk
```

### ধাপ ৪: `lib/config.dart`-এ IP ঠিক আছে কিনা চেক করো

```dart
static const String baseUrl = 'http://192.168.0.104:8000/api';
```

### ধাপ ৫: Laravel সার্ভার চালু করো

```bash
cd E:\app_project
php artisan serve --host=0.0.0.0 --port=8000
```

### ধাপ ৬: Flutter app চালাও

```bash
cd path\to\extracted\folder
flutter pub get
flutter run
```

**প্রথমবার Gradle 9.3.1 ডাউনলোড হবে** (নতুন ভার্সন, তাই আবার কিছুটা সময় নেবে — ধৈর্য ধরো, ৫-১৫ মিনিট)।

## Hard lock / Kiosk mode সেটআপ

Home, Recent, Back, notification shade এবং অন্য app পুরোপুরি বন্ধ করতে Android-এ
এই app-কে **Device Owner** হিসেবে provision করতে হবে। শুধু Device Admin,
Accessibility বা overlay permission দিয়ে Android এই restriction অনুমতি দেয় না।

Test device বা factory-reset করা device-এ, app install করার পর এবং কোনো Google/user
account যোগ করার আগে চালাও:

```bash
adb shell dpm set-device-owner xyz.alaminislam.parentalcontrol/.DeviceAdminReceiver
```

তারপর app খুলে Accessibility এবং Draw over other apps permission চালু করো। Device
Owner provision না হলে app lock screen দেখাবে, কিন্তু Android-এর system navigation
সম্পূর্ণ আটকানোর নিশ্চয়তা থাকবে না।

## যদি এবারও error আসে

Error-এর প্রথম কয়েক লাইন ("FAILURE:", "Error:", "Exception" অংশ) স্ক্রিনশট দিয়ে পাঠাও।
