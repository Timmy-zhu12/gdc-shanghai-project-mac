# Gemma4 4B Model Files

Place local offline model artifacts here for macOS testing:

```text
Models/gemma-4-4b-it-Q4_K_M.gguf
Models/gemma-4-4b-mmproj-Q4_0.gguf
```

These files are intentionally ignored by Git because they are large.

On macOS, configure the path to `llama-cli` in the app settings. On iPhone, the app keeps the same model-file contract, but a native llama.cpp/Metal backend must be added to the Xcode target before GGUF inference can run directly on device.

