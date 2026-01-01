<div align="center">
  <img width="256" height="256" alt="Macai App icon" src="https://github.com/user-attachments/assets/e5abd1b5-352f-41a1-92c4-8c159e873e6e" />
</div>
<h2 align="center">macai</h2>

<a href="#"><img alt="GitHub top language" src="https://img.shields.io/github/languages/top/Renset/macai"></a> <a href="#"><img alt="GitHub code size in bytes" src="https://img.shields.io/github/languages/code-size/Renset/macai"></a> <a href="https://github.com/Renset/macai/actions/workflows/swift-xcode.yml"><img alt="GitHub Workflow Status" src="https://img.shields.io/github/actions/workflow/status/Renset/macai/swift-xcode.yml"></a> <a href="https://github.com/Renset/macai/blob/main/LICENSE.md"><img alt="GitHub" src="https://img.shields.io/github/license/Renset/macai"></a>
<a href="https://github.com/Renset/macai/releases/latest"><img alt="GitHub all releases" src="https://img.shields.io/github/downloads/Renset/macai/total"></a>

macai (macOS AI) is a simple yet powerful native macOS AI chat client that supports most AI providers: ChatGPT, Claude, xAI (Grok), Google Gemini, Perplexity, Ollama, OpenRouter, and almost any OpenAI-compatible APIs.

<img width="1152" height="821" src="https://github.com/user-attachments/assets/734afb2c-9b77-4076-9f5d-d3d4c94f3f23" />

## Table of Contents
- [Downloads](#downloads)
  - [Manual](#manual)
  - [Homebrew](#homebrew)
- [Contributions](#contributions)
- [Why macai](#why-macai)
- [Run with ChatGPT, Claude, xAI or Google Gemini](#run-with-chatgpt-claude-xai-or-google-gemini)
- [Run with Ollama](#run-with-ollama)
- [System requirements](#system-requirements)
- [Project status](#project-status)
- [Build from source](#build-from-source)
- [iCloud Sync Configuration](#icloud-sync-configuration)
- [License](#license)

## Downloads

### Manual
Download [latest universal binary](https://github.com/Renset/macai/releases), notarized by Apple.

### Homebrew
Install macai cask with homebrew:
`brew install --cask macai`


## Contributions
Contributions are welcome. Take a look at [Issues page](https://github.com/Renset/macai/issues) to see already added features/bugs before creating new one. 
You can also support project by funding. This support is very important for me and allows to focus more on macai development.

<a href="https://www.buymeacoffee.com/renset1" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>


## Why macai
- **macOS-native and lightweight**
- **User-friendly**: simple setup, minimalist light/dark UI
- **Feature-rich**: vision, image generation, search, reasoning, import/export and more
- **iCloud Sync**: keep chats, messages, and settings in sync across devices
- **Private and secure**: no telemetry or usage tracking by macai (Note: Apple may collect anonymized telemetry when iCloud Sync is enabled)


## Run with ChatGPT, Claude, xAI or Google Gemini
To run macai with ChatGPT or Claude, you need to have an API token. API token is like password. You need to obtain the API token first to use any commercial LLM API. Most API services offer free credits on registering new account, so you can try most of them for free.
Here is how to get API token for all supported services:
- OpenAI: https://help.openai.com/en/articles/4936850-where-do-i-find-my-secret-api-key
- Claude: https://docs.anthropic.com/en/api/getting-started
- Google Gemini: https://ai.google.dev/gemini-api/docs/api-key
- xAI Grok: https://docs.x.ai/docs#models
- OpenRouter: https://openrouter.ai/docs/api-reference/authentication#using-an-api-key

If you are new to LLM and don't want to pay for the tokens, take a look Ollama. It supports dozens of OpenSource LLM models that can run locally on Apple M1/M2/M3/M4 Macs.

## Run with [Ollama](https://ollama.com)
Ollama is the open-source back-end for various LLM models. 
Run macai with Ollama is easy:
1. Install Ollama from the [official website](https://ollama.com)
2. Follow installation guides
3. After installation, select model (llama3.1 or llama3.2 are recommended) and pull model using command in terminal: `ollama pull <model>`
4. In macai settings, open API Service tab, add new API service (Expert mode) and select type Ollama":
   <img width="607" height="757" src="https://github.com/user-attachments/assets/19bc239b-f64d-4c8d-85a3-b05e5e727d2c" />

5. Select model, and default AI Assistant and save
6. Test and enjoy!

## System requirements
macOS 14.0 and later (both Intel and Apple chips are supported)

## Project status
Project is in the active development phase.

### Build from source

#### Option 1: With Apple Developer Account (Full Features)

If you have an Apple Developer account and want to build with iCloud Sync support:

1. Clone the repository: `git clone https://github.com/Renset/macai.git`
2. Open `macai.xcodeproj` in Xcode
3. Select your team in Signing & Capabilities
4. *(Optional)* To enable iCloud Sync in Debug builds, remove `DISABLE_ICLOUD` from Build Settings → Swift Compiler → Active Compilation Conditions
5. Build and run

> **Note:** By default, Debug builds have iCloud Sync disabled via the `DISABLE_ICLOUD` flag to simplify contributor setup. Release builds have iCloud Sync enabled.

#### Option 2: Without Apple Developer Account (No iCloud Sync)

If you don't have an Apple Developer account, you can still build and run the app without iCloud Sync:

**Using Xcode:**
1. Clone the repository: `git clone https://github.com/Renset/macai.git`
2. Open `macai.xcodeproj` in Xcode
3. Select the `macai` target → Build Settings tab
4. Search for `CODE_SIGN_ENTITLEMENTS`
5. Change the value from `macai/macai.entitlements` to `macai/macai-no-icloud.entitlements`
6. In Signing & Capabilities, set "Signing Certificate" to "Sign to Run Locally"
7. Build and run

**Using Command Line:**
```bash
git clone https://github.com/Renset/macai.git
cd macai
xcodebuild -scheme macai \
  -configuration Debug \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_ENTITLEMENTS="macai/macai-no-icloud.entitlements" \
  DEVELOPMENT_TEAM="" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

> **Note:** The app built without iCloud entitlements will work normally, but the iCloud Sync feature will not be available. All other features (chat, API services, personas, etc.) will work as expected.

### iCloud Sync Configuration

#### For Contributors (Debug Builds)

iCloud Sync is **disabled by default** in Debug builds via the `DISABLE_ICLOUD` compiler flag. This simplifies the development setup and avoids CloudKit-related signing issues for contributors without an Apple Developer account.

**To enable iCloud Sync in Debug builds:**
1. Select the `macai` target → Build Settings tab
2. Search for `SWIFT_ACTIVE_COMPILATION_CONDITIONS` (or "Active Compilation Conditions")
3. Remove `DISABLE_ICLOUD` from the value (leaving just `DEBUG`)
4. Ensure you have proper entitlements and signing configured (see below)

#### For Forks / Custom Builds

If you want iCloud Sync to work in a fork or custom build, you must use your own CloudKit container:

1. Create a CloudKit container in your Apple Developer account
2. Enable the iCloud capability for the macai target in Xcode, and add your container
3. Update the `CloudKitContainerIdentifier` value in `macai/Info.plist` to your container ID
4. Ensure your app's bundle identifier matches the one you registered for the container
5. Remove `DISABLE_ICLOUD` from Active Compilation Conditions if present

If `CloudKitContainerIdentifier` is missing, the app falls back to the default container.

## License
[Apache-2.0](https://github.com/Renset/macai/blob/main/LICENSE.md)
