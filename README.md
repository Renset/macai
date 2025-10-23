<div align="center">
<img width="256" src="https://github.com/user-attachments/assets/3b5b5587-a83f-4133-b00d-9a8c509661df" />
</div>
<h2 align="center">macai</h2>

<a href="#"><img alt="GitHub top language" src="https://img.shields.io/github/languages/top/Renset/macai"></a> <a href="#"><img alt="GitHub code size in bytes" src="https://img.shields.io/github/languages/code-size/Renset/macai"></a> <a href="https://github.com/Renset/macai/actions/workflows/swift-xcode.yml"><img alt="GitHub Workflow Status" src="https://img.shields.io/github/actions/workflow/status/Renset/macai/swift-xcode.yml"></a> <a href="https://github.com/Renset/macai/blob/main/LICENSE.md"><img alt="GitHub" src="https://img.shields.io/github/license/Renset/macai"></a>
<a href="https://github.com/Renset/macai/releases/latest"><img alt="GitHub all releases" src="https://img.shields.io/github/downloads/Renset/macai/total"></a>

macai (macOS AI) is a simple yet powerful native macOS AI chat client that supports most AI providers: ChatGPT, Claude, xAI (Grok), Google Gemini, Perplexity, Ollama, OpenRouter, and almost any OpenAI-compatible APIs.

<img width="1152" height="821" src="https://github.com/user-attachments/assets/734afb2c-9b77-4076-9f5d-d3d4c94f3f23" />


## Downloads

### Manual
Download [latest universal binary](https://github.com/Renset/macai/releases), notarized by Apple.

### Homebrew
Install macai cask with homebrew:
`brew install --cask macai`

### Build from source
Checkout main branch and open project in Xcode 14.3 or later

## Contributions
Contributions are welcome. Take a look at [Issues page](https://github.com/Renset/macai/issues) to see already added features/bugs before creating new one. 
You can also support project by funding. This support is very important for me and allows to focus more on macai development.

<a href="https://www.buymeacoffee.com/renset1" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>


## Why macai
- **macOS-native and lightweight**
- **User-friendly**: simple setup, minimalist light/dark UI
- **Feature-rich**: vision, image generation, search, reasoning, import/export and more
- **Private and secure**: no telemetry or usage tracking


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



## License
[Apache-2.0](https://github.com/Renset/macai/blob/main/LICENSE.md)
