# Android APK 建置流程

這份文件只講目前這個專案在本機如何快速建出可安裝的 Android APK。

## 適用情境

- 你想先建一個 `debug` APK 自己安裝使用
- 你想確認 Android 端目前能正常編譯
- 你想知道 APK 產物會放在哪裡

## 前置需求

1. 已安裝 JDK 17 或以上
2. 已安裝 Android SDK
3. 專案內已有 `android/local.properties`

目前你的機器預設可用設定如下：

```properties
sdk.dir=/Users/lhf/Library/Android/sdk
```

檔案位置：

```text
/Users/lhf/Documents/AI 記帳/android/local.properties
```

## 最簡單流程：建 `debug` APK

在專案根目錄執行：

```bash
cd '/Users/lhf/Documents/AI 記帳/android'
./gradlew assembleDebug
```

如果成功，APK 會在這裡：

```text
/Users/lhf/Documents/AI 記帳/android/app/build/outputs/apk/debug/app-debug.apk
```

## 建完後如何安裝到手機

如果手機已開啟 USB 偵錯，並且 `adb` 能看到裝置：

```bash
cd '/Users/lhf/Documents/AI 記帳/android'
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

說明：

- `-r` 代表覆蓋安裝現有版本
- 如果簽名不同，可能仍需要先手動刪除舊版本再安裝

## 建置前先跑一次測試

如果你想先確認目前 Android 端核心邏輯沒壞，再 build：

```bash
cd '/Users/lhf/Documents/AI 記帳/android'
./gradlew testDebugUnitTest
./gradlew assembleDebug
```

## 常用指令

### 1. 只建 APK

```bash
cd '/Users/lhf/Documents/AI 記帳/android'
./gradlew assembleDebug
```

### 2. 先測試再建 APK

```bash
cd '/Users/lhf/Documents/AI 記帳/android'
./gradlew testDebugUnitTest
./gradlew assembleDebug
```

### 3. 乾淨重建

如果遇到奇怪快取問題：

```bash
cd '/Users/lhf/Documents/AI 記帳/android'
./gradlew clean assembleDebug
```

## 常見問題

### 找不到 Android SDK

症狀：

- Gradle 提示找不到 SDK
- 或出現 `SDK location not found`

處理：

1. 檢查 `android/local.properties` 是否存在
2. 確認裡面的 `sdk.dir` 指向正確路徑

目前你的正確路徑應該是：

```properties
sdk.dir=/Users/lhf/Library/Android/sdk
```

### JDK 版本不對

先檢查：

```bash
java -version
```

建議顯示 `17` 或以上。

### `gradlew: Permission denied`

執行：

```bash
cd '/Users/lhf/Documents/AI 記帳/android'
chmod +x gradlew
./gradlew assembleDebug
```

### 裝不上手機

先檢查裝置是否有被 adb 看到：

```bash
adb devices
```

如果沒有看到手機：

1. 檢查 USB 偵錯是否已開啟
2. 檢查手機是否有按下「允許 USB 偵錯」
3. 重新插拔 USB 或重開 adb

可嘗試：

```bash
adb kill-server
adb start-server
adb devices
```

## 目前建議

如果只是自用，優先用這條：

```bash
cd '/Users/lhf/Documents/AI 記帳/android'
./gradlew testDebugUnitTest
./gradlew assembleDebug
```

然後直接安裝：

```bash
adb install -r /Users/lhf/Documents/AI 記帳/android/app/build/outputs/apk/debug/app-debug.apk
```
