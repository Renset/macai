<div align="center">
<img width="256" src="https://github.com/user-attachments/assets/3b5b5587-a83f-4133-b00d-9a8c509661df" />
</div>
<h2 align="center">macai</h2>

<a href="#"><img alt="GitHub top language" src="https://img.shields.io/github/languages/top/Renset/macai"></a> <a href="#"><img alt="GitHub code size in bytes" src="https://img.shields.io/github/languages/code-size/Renset/macai"></a> <a href="https://github.com/Renset/macai/actions/workflows/swift-xcode.yml"><img alt="GitHub Workflow Status" src="https://img.shields.io/github/actions/workflow/status/Renset/macai/swift-xcode.yml"></a> <a href="https://github.com/Renset/macai/blob/main/LICENSE.md"><img alt="GitHub" src="https://img.shields.io/github/license/Renset/macai"></a>
<a href="https://github.com/Renset/macai/releases/latest"><img alt="GitHub all releases" src="https://img.shields.io/github/downloads/Renset/macai/total"></a>

macai (macOS AI) is a simple yet powerful native macOS AI chat client that supports most AI providers: ChatGPT, Claude, xAI (Grok), Google Gemini, Perplexity, Ollama, OpenRouter, and almost any OpenAI-compatible APIs.

<img width="1322" alt="macai window" src="https://github.com/user-attachments/assets/3a9677e4-0d75-4d19-9d5f-3d74b896fcf8">

## Downloads

### Manual
Download [latest universal binary](https://github.com/Renset/macai/releases), notarized by Apple.

### Homebrew
Install macai cask with homebrew:
`brew install --cask macai`

### Build from source
Checkout main branch and open project in Xcode 14.3 or later

## Contributions
Contributions are welcome. Take a look at [Issues page](https://github.com/Renset/macai/issues) to see already added features/bugs before creating new one. If you plan to fix bug or implement a feature, select any of the open _unassigned_ issues, and feel free to start working on it.

You can also support project by funding. This support is very important for me and allows to focus on macai development.

<a href="https://www.buymeacoffee.com/renset1" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>


## Features

### Core Capabilities
- Native macOS application built with SwiftUI for optimal performance and system integration
- Lightning fast search across all chats, messages, and personas
- Multi-LLM support including:
  - OpenAI ChatGPT models (gpt-4o, o1-mini, o1-preview and other)
  - Anthropic Claude
  - Google Gemini
  - xAI Grok
  - Perplexity
  - OpenRouter
  - Local LLMs via [Ollama](https://ollama.com)
  - Any other OpenAI-compatible API

### Advanced Chat Features
- Image uploads support for certain APIs and models
- AI Personas with customizable:
  - System instructions
  - Temperature settings
- Intelligent message handling:
  - Streamed responses for real-time interaction
  - Adjustable chat context size
  - Automatic chat naming
- Rich content support:
  - Syntax-highlighted code blocks
  - Interactive HTML/CSS/JavaScript preview
  - Formatted tables with CSV/JSON export
  - LaTeX equation rendering

### Privacy & Data Control
- 100% local data storage
- No telemetry or usage tracking
- Built-in backup/restore functionality with JSON export
- Complete control over API configurations and keys

### User Experience
- System-native light/dark theme 
- Per-chat customizable system instructions
- Clean, native macOS interface
- Minimal resource usage compared to Electron-based alternatives

## Run with ChatGPT, Claude, xAI or Google Gemini
To run macai with ChatGPT or Claude, you need to have an API token. API token is like password. You need to obtain the API token first to use any commercial LLM API. Most API services offer free credits on registering new account, so you can try most of them for free.
Here is how to get API token for all supported services:
- OpenAI: https://help.openai.com/en/articles/4936850-where-do-i-find-my-secret-api-key
- Claude: https://docs.anthropic.com/en/api/getting-started
- Google Gemini: https://ai.google.dev/gemini-api/docs/api-key (free models available 🔥)
- xAI Grok: https://docs.x.ai/docs#models
- OpenRouter: https://openrouter.ai/docs/api-reference/authentication#using-an-api-key (> 50 free models 🔥)

If you are new to LLM and don't want to pay for the tokens, take a look Ollama. It supports dozens of OpenSource LLM models that can run locally on Apple M1/M2/M3/M4 Macs.

## Run with [Ollama](https://ollama.com)
Ollama is the open-source back-end for various LLM models. 
Run macai with Ollama is easy-peasy:
1. Install Ollama from the [official website](https://ollama.com)
2. Follow installation guides
3. After installation, select model (llama3.1 or llama3.2 are recommended) and pull model using command in terminal: `ollama pull <model>`
4. In macai settings, open API Service tab, add new API service and select type "ollama":
   <img width="628" src="https://github.com/user-attachments/assets/2dfb826b-3c1e-4c44-b5e6-e85f35fe76d7" />
5. Select model, and default AI Persona and save
6. Test and enjoy!

## System requirements
macOS 13.0 and later (both Intel and Apple chips are supported)

## Project status
Project is in the active development phase.

## Screenshots

### Starting screen
<img width="938" alt="Welcome screen of macai ChatGPT client: light themed window with an icon of happy looking retro-futuristic robot in front of sparkles" src="https://github.com/user-attachments/assets/ad64eba4-adfa-4353-9f05-f9d9124375f4" />

### Settings: API Services list
<img width="562" alt="Settings window with API Services list" src="https://github.com/user-attachments/assets/61ec4db2-56e9-4b78-b6b7-f00fe2e24909" />

### Settings: AI Persona editor
<img width="560" alt="Settings window with AI Persona editor" src="https://github.com/user-attachments/assets/9168a06a-9614-47b7-8353-365ef8b76c2b" />

### Chat customization
API Service, AI Persona and system message are customizable in any chat anytime
<img width="1063" alt="Chat window with system message editing" src="https://github.com/user-attachments/assets/c808340a-aad2-4dd2-912f-0bb6d47918ba" />

### Search

https://github.com/user-attachments/assets/84d2d813-59bc-4a1a-96af-fc72641d1658





## License
[Apache-2.0](https://github.com/Renset/macai/blob/main/LICENSE.md)
