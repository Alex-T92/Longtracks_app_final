# 📻 Long Tracks Radio - Application Android/iOS

Application mobile Flutter pour Long Tracks Radio.

## ⚡ Installation Rapide

### 1️⃣ Prérequis
- **Flutter** installé : https://docs.flutter.dev/get-started/install
- **VS Code** ou Android Studio

### 2️⃣ Installation
```bash
cd longtracks_app_final
flutter pub get
```

### 3️⃣ Configuration IMPORTANTE
**Ouvrez `lib/main.dart` ligne 132** et remplacez :
```dart
final String _streamUrl = 'METTEZ_VOTRE_URL_DE_STREAM_ICI.mp3';
```

Par votre URL de stream MP3/AAC directe (PAS l'URL du player web).

**Exemple :**
```dart
final String _streamUrl = 'https://votre-radio.ice.infomaniak.ch/votre-radio-128.mp3';
```

### 4️⃣ Tester
```bash
# Sur Chrome (rapide)
flutter run -d chrome

# Sur Android (si émulateur lancé)
flutter run

# Sur un téléphone USB
flutter run
```

## 📱 Compiler l'APK Android

```bash
flutter build apk --release
```

L'APK sera dans : `build/app/outputs/flutter-apk/app-release.apk`

**Transférez-le sur votre téléphone et installez-le !**

## 🎨 Fonctionnalités

✅ Streaming audio en direct  
✅ Lecture/Pause  
✅ Contrôle du volume  
✅ Programme de la semaine  
✅ Interface sombre orange/noir  
✅ Animation vinyle pendant la lecture  

## ⚠️ Problèmes courants

### "Stream URL not found"
→ Vérifiez l'URL dans `lib/main.dart` ligne 132

### "flutter pub get" échoue
```bash
flutter clean
flutter pub get
```

### L'audio ne joue pas
→ Assurez-vous que l'URL finit par `.mp3` ou `.aac` (PAS une URL de player HTML)

## 📧 Support

contact@long-tracks-radio.com

---

© 2025 Long Tracks Radio
