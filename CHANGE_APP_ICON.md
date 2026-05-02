# How to Change the Kratos Admin App Icon

## ✅ Automated Method (Recommended)

### Step 1: Prepare Your Icon
1. Create a **square PNG image** (1024x1024px recommended)
2. Use a transparent or solid background
3. Make sure your logo is centered and has some padding
4. Save it as `app_icon.png`

### Step 2: Add Your Icon to the Project
1. Create the directory: `assets/icon/` in your project root
2. Place your `app_icon.png` file in `assets/icon/`

Your structure should look like:
```
kratos-gym-mobile/
├── assets/
│   └── icon/
│       └── app_icon.png  ← Your 1024x1024px icon here
├── lib/
├── android/
├── ios/
└── pubspec.yaml
```

### Step 3: Install the Package
Run this command in your terminal:
```bash
flutter pub get
```

### Step 4: Generate Icons
Run this command to automatically generate all icon sizes for iOS and Android:
```bash
flutter pub run flutter_launcher_icons
```

### Step 5: Rebuild Your App
```bash
# For Android
flutter build apk --release

# For iOS
flutter build ios --release
```

---

## 🎨 Advanced: Adaptive Icons (Android 8.0+)

If you want a modern adaptive icon for Android (with background and foreground):

1. Uncomment these lines in `pubspec.yaml`:
```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/icon/app_icon.png"
  adaptive_icon_background: "#FFFFFF"  # Background color
  adaptive_icon_foreground: "assets/icon/app_icon_foreground.png"  # Foreground image
```

2. Create two images:
   - `app_icon_foreground.png` - Your logo with transparency (centered, about 60% of canvas)
   - Background can be a solid color (specified in hex) or an image

3. Run the generator again:
```bash
flutter pub run flutter_launcher_icons
```

---

## 📱 What Gets Generated

### Android Icons
The package will create icons in these sizes:
- mipmap-mdpi: 48x48px
- mipmap-hdpi: 72x72px
- mipmap-xhdpi: 96x96px
- mipmap-xxhdpi: 144x144px
- mipmap-xxxhdpi: 192x192px

### iOS Icons
The package will create all required iOS icon sizes:
- 20x20, 29x29, 40x40, 60x60, 76x76, 83.5x83.5, 1024x1024
- All in @1x, @2x, and @3x variants as needed

---

## 🚀 Current Configuration

Your `pubspec.yaml` is already configured with:
- ✅ `flutter_launcher_icons` package installed
- ✅ Configuration pointing to `assets/icon/app_icon.png`

**Next Steps:**
1. Create `assets/icon/` folder
2. Add your `app_icon.png` (1024x1024px)
3. Run `flutter pub get`
4. Run `flutter pub run flutter_launcher_icons`
5. Rebuild your app

---

## 💡 Tips

1. **Icon Design:**
   - Keep it simple and recognizable at small sizes
   - Use high contrast
   - Avoid text (it becomes unreadable at small sizes)
   - Leave some padding around the edges

2. **Testing:**
   - Test on both Android and iOS devices
   - Check how it looks in different themes (light/dark mode)
   - Verify it displays correctly in app drawer, home screen, and settings

3. **iOS Guidelines:**
   - iOS automatically adds rounded corners
   - Don't include rounded corners in your source image
   - Fill the entire canvas

4. **Android Guidelines:**
   - For adaptive icons, center your logo
   - Background color should match your brand
   - Foreground should have transparency

---

## 📋 Quick Reference Commands

```bash
# Install dependencies
flutter pub get

# Generate icons
flutter pub run flutter_launcher_icons

# Clean and rebuild (Android)
flutter clean
flutter build apk --release

# Clean and rebuild (iOS)
flutter clean
flutter build ios --release
```
