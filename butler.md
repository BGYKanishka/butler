# Butler Architecture: Visual End-to-End System Diagram

```mermaid
graph TD
    classDef input fill:#e1f5fe,stroke:#0288d1,stroke-width:2px,color:#000;
    classDef process fill:#fff3e0,stroke:#f57c00,stroke-width:2px,color:#000;
    classDef storage fill:#e8f5e9,stroke:#388e3c,stroke-width:2px,color:#000;
    classDef model fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px,color:#000;
    classDef output fill:#e8eaf6,stroke:#3f51b5,stroke-width:2px,color:#000;

    %% -------------------------------------------------------------
    %% LAYER 1: AUDIO CAPTURE & CONVERSION
    %% -------------------------------------------------------------
    subgraph "Layer 1: Real-Time Audio Capture & Ring Buffering"
        MIC["🎤 <b>User Microphone (AVAudioEngine)</b><br/><i>MicrophoneCaptureService.swift</i><br/>─────────────────────────────<br/>• Captures local user voice in real time via native AVAudioEngine<br/>• Attaches non-blocking 4096-frame audio tap and auto-recovers from Bluetooth/USB disconnects"]:::input --> CONV_MIC["🎛️ <b>Audio Converter (16kHz Mono)</b><br/><i>AudioConverter.swift</i><br/>─────────────────────────────<br/>• Resamples microphone audio to Whisper's native input format<br/>• Converts hardware rates (44.1k/48k stereo) to 16kHz Float32 mono directly on audio thread with zero heap allocations"]:::process
        
        SYS["💻 <b>System Audio Capture (Interviewer)</b><br/><i>SystemAudioCaptureService.swift</i><br/>─────────────────────────────<br/>• Captures remote meeting speech directly via macOS ScreenCaptureKit<br/>• Configures audio-only capture stream and drops video frames to save CPU and battery"]:::input --> CONV_SYS["🎛️ <b>Audio Converter (16kHz Mono)</b><br/><i>AudioConverter.swift</i><br/>─────────────────────────────<br/>• Resamples meeting audio stream to uniform Whisper format<br/>• Downmixes multi-channel system audio to 16kHz mono Float32 PCM directly in memory"]:::process
        
        CONV_MIC --> RB_MIC[("🔄 <b>Mic AudioRingBuffer (20s)</b><br/><i>AudioRingBuffer.swift</i><br/>─────────────────────────────<br/>• Buffers continuous user microphone audio in a 20-second circular array<br/>• Holds 320,000 Float32 samples with os_unfair_lock so audio threads never block while old samples overwrite")]:::storage
        
        CONV_SYS --> RB_SYS[("🔄 <b>Sys AudioRingBuffer (20s)</b><br/><i>AudioRingBuffer.swift</i><br/>─────────────────────────────<br/>• Buffers continuous remote meeting audio in a 20-second circular array<br/>• Holds 320,000 Float32 samples, using lock-free circular memory copies via memcpy and tracking totalWritten frames")]:::storage
    end

    %% -------------------------------------------------------------
    %% LAYER 2: VAD & SLICING
    %% -------------------------------------------------------------
    subgraph "Layer 2: Voice Activity Detection (VAD) & Adaptive Slicing"
        RB_MIC --> VAD_TICK["⏱️ <b>VAD Polling Engine (Every 100ms)</b><br/><i>AudioSessionCoordinator.swift</i><br/>─────────────────────────────<br/>• Periodically samples recent audio to detect speech energy<br/>• Runs DispatchSourceTimer every 100ms on vadQueue, reads 1,600 samples (0.1s), and computes RMS sound power"]:::process
        RB_SYS --> VAD_TICK
        
        VAD_TICK --> VAD_EVAL{"📊 <b>Dual-Threshold Energy Gate</b><br/><i>VoiceActivityDetector.swift</i><br/>─────────────────────────────<br/>• Evaluates sound energy against source-specific acoustic thresholds<br/>• Mic threshold (0.010) rejects keyboard typing and breathing; system threshold (0.005) captures quiet remote voices, saving 100% idle GPU"}:::process
        
        VAD_EVAL -->|Speech Confirmed| ONSET["🎯 <b>Speech Onset Recorded</b><br/>─────────────────────────────<br/>• Marks the exact audio timestamp when voice energy begins<br/>• Preserves 1.0s pre-roll buffer so initial consonants (p, t, k) and opening words are never cut off"]:::process
        
        VAD_EVAL -->|Speech Exceeds 10s| SLICE_FORCE["✂️ <b>Continuous Speech Force-Slice</b><br/>─────────────────────────────<br/>• Prevents long uninterrupted sentences from causing transcription lag<br/>• Force-slices continuous speech at 10s mark while maintaining 1.5s boundary overlap to prevent dropped words"]:::process
        
        VAD_EVAL -->|Speech Ended| SLICE_END["✂️ <b>Natural Pause Slice</b><br/>─────────────────────────────<br/>• Detects natural speech completion during conversational pauses<br/>• Slices when silence persists; discards audio under 0.6s to filter coughs, clicks, and background noise"]:::process
        
        SLICE_FORCE --> AUDIO_CHUNK["📦 <b>Clean Audio Segment (Float32 PCM)</b><br/>─────────────────────────────<br/>• Emits normalized, trimmed speech segments ready for Whisper<br/>• Delivers contiguous Float32 PCM audio arrays bounded between 0.6s and 10s"]:::output
        SLICE_END --> AUDIO_CHUNK
    end

    %% -------------------------------------------------------------
    %% LAYER 3: TRANSCRIPTION PIPELINE
    %% -------------------------------------------------------------
    subgraph "Layer 3: Local Whisper Speech-to-Text & Transcript Assembly"
        AUDIO_CHUNK --> WHISPER["🗣️ <b>Local Whisper Engine (whisper.cpp)</b><br/><i>WhisperEngine.swift</i><br/>─────────────────────────────<br/>• Transcribes raw speech to text 100% locally and privately on Apple Silicon Metal GPU<br/>• Runs whisper.cpp (ggml-small.en) using direct C++ Float32 pointer passing with zero disk I/O"]:::model

        VOCAB["📚 <b>Project Vocabulary Prompt</b><br/>─────────────────────────────<br/>• Biases the speech recognition engine toward project-specific code terminology<br/>• Injects up to 150 top symbols and filenames into Whisper initialPrompt (~480 chars) for phonetic steering"]:::storage -.-> WHISPER
        
        WHISPER -->|Partial Tokens| PARTIAL_SEG["⚡ <b>Live Partial Transcript</b><br/>─────────────────────────────<br/>• Streams speculative mid-sentence transcripts every 1.5 seconds<br/>• Emits early unconfirmed tokens to trigger speculative retrieval and give the LLM an early head start"]:::output
        WHISPER -->|Final Audio Segment| FINAL_SEG["📝 <b>Completed Audio Transcript</b><br/>─────────────────────────────<br/>• Produces confirmed text upon sentence completion or natural pause<br/>• Emits complete sentence segments with millisecond timestamps and source attribution (User vs System)"]:::output
        
        FINAL_SEG --> FILTER["🛡️ <b>Noise & Hallucination Filter</b><br/>─────────────────────────────<br/>• Cleans transcript text of hallucinated patterns and acoustic artifacts<br/>• Strips music markers, subtitle artifacts, blank tokens, and repetitive Whisper looping phrases"]:::process
        
        FILTER --> CORRECTOR["✏️ <b>Developer Jargon Corrector</b><br/><i>TranscriptCorrector.swift</i><br/>─────────────────────────────<br/>• Deterministically repairs known speech-to-text mishearings for developer terms<br/>• Runs marker-gated regex rules: converts frag system → RAG system, k v cash → KV cache, guff → GGUF, sequel lite → SQLite"]:::process
        
        CORRECTOR --> ASSEMBLER["🧩 <b>Transcript Assembler - Suffix-Prefix O(n)</b><br/><i>TranscriptAssembler.swift</i><br/>─────────────────────────────<br/>• Stitches overlapping audio segments into continuous, fluent sentences<br/>• Performs linear-time suffix-prefix word matching between segments to eliminate duplicated words across boundaries"]:::process
        
        ASSEMBLER --> TURNS["💬 <b>Conversational History (ContextManager)</b><br/><i>ContextManager.swift</i><br/>─────────────────────────────<br/>• Maintains a chronological multi-turn conversational dialogue history<br/>• Stores alternating speaker turns (User vs Interviewer) to preserve conversational context for follow-up questions"]:::storage
    end

    %% -------------------------------------------------------------
    %% LAYER 4: CODEBASE INDEXING & HYBRID SEARCH (RAG)
    %% -------------------------------------------------------------
    subgraph "Layer 4: Codebase Analysis, SQLite Storage & Real-Time Code Indexing (RAG)"
        CODE_SRC[("📂 <b>Local Project Files</b><br/>─────────────────────────────<br/>• Serves as the local source of truth for codebase intelligence<br/>• Scans up to 5,000 files, filtering out build directories, node_modules, .git, and secrets")]:::storage

        %% --- Track A: How Butler Analyzes the Project ---
        CODE_SRC --> PROJ_ANALYZER["🔍 <b>Project Scanner & Semantic Analyzer</b><br/><i>ProjectScanner.swift & ProjectAnalyzer.swift</i><br/>─────────────────────────────<br/>• Discovers overall project structure, tech stack, and primary domain concepts<br/>• Parses manifests (package.json, Cargo.toml, Package.swift) for dependencies and language ratios<br/>• Distills top 150 symbols and README headers into a candidate project identity"]:::process

        PROJ_ANALYZER --> VOCAB_SYNC["📚 <b>Dual-Purpose Vocabulary Sync</b><br/><i>UserDefaults & TranscriptCorrector</i><br/>─────────────────────────────<br/>• Keeps speech recognition and text correction aligned with project jargon<br/>• Feeds Whisper initialPrompt (~480 chars) with top symbols for phonetic spelling guidance<br/>• Provides safety markers to TranscriptCorrector so technical jargon rules only fire when relevant"]:::storage
        VOCAB_SYNC -.-> VOCAB
        VOCAB_SYNC -.-> CORRECTOR

        PROJ_ANALYZER --> KV_WARM["⚡ <b>KV-Cache State Warmer</b><br/><i>ProjectContextManager.swift</i><br/>─────────────────────────────<br/>• Eliminates startup LLM evaluation lag for static project context<br/>• Formats project summary as system prompt prefix and computes KV attention tensors on Metal GPU<br/>• Persists state to butler_project_memory.bin for &lt;20ms restoration via llama_state_load_file"]:::process

        %% --- Track B: How SQLite Works & Why Indexing Matters ---
        CODE_SRC --> CHANGE_GATE{"⚡ <b>3-Tier Change Detection Engine</b><br/><i>ProjectIndexCoordinator.swift</i><br/>─────────────────────────────<br/>• Filters untouched files so background indexing uses minimal CPU and battery<br/>• Tier 1: Microsecond mtime and size comparison against SQLite record<br/>• Tier 2: SHA-256 content hash check if timestamp shifted, avoiding re-indexing identical text<br/>• Tier 3: Triggers re-indexing only on genuinely modified files inside an atomic transaction"}:::process

        CHANGE_GATE -->|Unchanged: 99% of Files| SKIP_GATE["⚡ <b>Zero-Cost Bypass</b><br/>─────────────────────────────<br/>• Skips unchanged codebase files during active development<br/>• Bypasses ~99% of files with 0ms CPU and 0 disk reads, preventing battery drain"]:::process
        CHANGE_GATE -->|File Deleted from Disk| DEL_CASCADE["🗑️ <b>Cascade Pruning</b><br/>─────────────────────────────<br/>• Automatically purges deleted files and stale index entries<br/>• Foreign key ON DELETE CASCADE clears linked records in symbols, chunks, chunks_fts, and refs"]:::process --> SQLITE_DB

        CHANGE_GATE -->|File Modified or Added| CHUNKER["✂️ <b>AST Semantic Code Chunker</b><br/><i>CodeChunker.swift & SymbolExtractor.swift</i><br/>─────────────────────────────<br/>• Splits code into complete semantic units (functions, classes, structs) instead of line count cuts<br/>• Language regexes (Swift, Go, Py, TS, Rust, Java, C++) detect declaration headers<br/>• Tracks brace depth { ... } and indentation to find exact boundaries without slicing functions in half<br/>• Maps enclosing parent types (e.g. AudioRingBuffer.push) and soft-splits functions &gt;1400 chars"]:::process

        CHUNKER --> SQLITE_DB[("🗄️ <b>Embedded SQLite Database (WAL Mode)</b><br/><i>IndexSchema.swift & SQLiteDatabase.swift</i><br/>─────────────────────────────<br/>• Persists, indexes, and organizes code chunks, symbols, and relationships locally on disk<br/>• Relational tables: files (metadata, hashes), symbols (declarations, parent), chunks (slices, lines), refs (graph)<br/>• Insertion order: files → symbols (gets IDs) → chunks (foreign keys) → chunks_fts (virtual table)<br/>• Indexing & Concurrency: symbols_norm B-Tree index, FTS5 BM25 text index, and WAL mode for non-blocking reads")]:::storage

        CHUNKER --> GRAPH_BUILD["🕸️ <b>1-Hop Static Knowledge Graph Builder</b><br/><i>ProjectIndexCoordinator.swift</i><br/>─────────────────────────────<br/>• Maps caller-callee dependencies so the AI can pull in referenced symbol definitions<br/>• Tokenizes new chunks for identifiers (4+ chars), filtering common keywords (main, init, self)<br/>• Matches identifiers against unique project symbols and inserts directed edges into refs table"]:::process
        GRAPH_BUILD --> SQLITE_DB

        SQLITE_DB -.->|Invalidate Cache on Sync| LEX_CACHE[("🧠 <b>In-Memory SymbolLexicon Cache</b><br/><i>HybridProjectRetriever.swift</i><br/>─────────────────────────────<br/>• Delivers sub-millisecond symbol and file lookups without disk I/O<br/>• Caches normalized symbols and file paths in RAM dictionaries (60s TTL) for partial 1.5s speech queries<br/>• Automatically invalidated and refreshed whenever index sync finishes")]:::storage

        %% --- Track C: Real-Time Spoken Retrieval (RAG in Action) ---
        TURNS -->|Final Utterance: Full Search| ROUTER["🗺️ <b>Spoken Query Router & Concept Expander</b><br/><i>QueryRouter.swift</i><br/>─────────────────────────────<br/>• Resolves conversational speech into structured codebase search targets<br/>• Borrows prior turn context for follow-ups and resolves pronouns (it, that) to active symbols<br/>• Expands spoken cues (rag, vad, kv) to code keywords and classifies query intent"]:::process
        PARTIAL_SEG -.->|Speculative Preview: cheapOnly Mode| ROUTER
        LEX_CACHE -.->|Instant In-Memory Match| ROUTER

        ROUTER --> RETRIEVE["🔀 <b>Multi-Channel Search Engine</b><br/><i>HybridProjectRetriever.swift</i><br/>─────────────────────────────<br/>• Discovers candidate code across three distinct retrieval channels in parallel<br/>• Channel 1: symbols_norm B-Tree index lookup for exact (1.0) and prefix (0.5) symbol matches<br/>• Channel 2: Path pattern matching (1.0) on files table; Channel 3: SQLite FTS5 BM25 text search<br/>• Partial 1.5s speech previews run in cheapOnly mode, skipping prefix and graph lookups"]:::process
        SQLITE_DB <--> RETRIEVE

        RETRIEVE --> RRF_FUSION["⚖️ <b>Reciprocal Rank Fusion (RRF, k=60)</b><br/><i>HybridProjectRetriever.swift</i><br/>─────────────────────────────<br/>• Merges multi-channel ranks into a single balanced relevance order<br/>• Combines rankings via score += weight / (60 + rank + 1), dynamically weighting channels by intent<br/>• Fetches all candidate chunks from SQLite in a single batch WHERE id IN (...) query to eliminate N+1 latency"]:::process

        RRF_FUSION --> POST_PROC["🛡️ <b>Post-Processing Guardrails</b><br/><i>HybridProjectRetriever.swift</i><br/>─────────────────────────────<br/>• Filters out low-quality snippets and pulls in connected code definitions<br/>• Applies 0.6x score penalty to test files, caps at 2 chunks per file, and drops &gt;50% line overlaps<br/>• Traverses 1-hop refs table for top 3 chunks to automatically attach definitions of called functions"]:::process
        SQLITE_DB --> POST_PROC

        POST_PROC --> WEAK_GATE{"🛡️ <b>Weak Signal Gate</b><br/><i>HybridProjectRetriever.swift</i><br/>─────────────────────────────<br/>• Prevents small talk or casual greetings from injecting irrelevant code<br/>• Evaluates top fused score against threshold (0.6/61 with question cues, 1.2/61 without)<br/>• Completely drops retrieval context if query has no technical intent"}:::process

        WEAK_GATE -->|Score Below Threshold| DROP_CTX["🚫 <b>Empty Context Injected</b><br/>─────────────────────────────<br/>• Keeps the prompt clean during casual banter<br/>• Passes no code snippets into the model prompt, preventing hallucinations during small talk"]:::output

        WEAK_GATE -->|Score Above Threshold| DISK_FRESH{"⏱️ <b>Live Disk Freshness Verification</b><br/><i>HybridProjectRetriever.swift</i><br/>─────────────────────────────<br/>• Guarantees the AI never receives outdated code while you edit in your IDE<br/>• Inspects live file on disk via FileManager right before generation<br/>• Drops chunk immediately if disk mtime and size diverge from stored SQLite record"}:::process

        DISK_FRESH -->|Fresh Chunks| CTX_ASSEMBLE["📋 <b>Context Assembler & Token Budgeting</b><br/><i>ContextAssembler.swift</i><br/>─────────────────────────────<br/>• Formats winning code chunks into a token-budgeted prompt block<br/>• Renders snippets as Markdown with file paths and line ranges, appending RELATED footer for graph symbols<br/>• Truncates oversized text strictly to stay within token limits (2,500-10,000 tokens)"]:::process
    end

    %% -------------------------------------------------------------
    %% LAYER 5: PROMPT ASSEMBLY, INTENT GATING & LLM INFERENCE
    %% -------------------------------------------------------------
    subgraph "Layer 5: Prompt Assembly, Intent Gating & LLM Inference"
        TURNS --> RG_TRIGGER["⚡ <b>Response Generator (@MainActor)</b><br/><i>ResponseGenerator.swift</i><br/>─────────────────────────────<br/>• Coordinates response generation on the main actor to prevent collision<br/>• Serializes requests and enforces a strict 250ms race budget for code retrieval so SQLite lookups never stall speech answers"]:::process
        PARTIAL_SEG -.->|Speculative 1.5s| RG_TRIGGER
        
        CTX_ASSEMBLE -->|RELEVANT CODE Block| PROMPT_BUILD["📝 <b>Prompt Builder (Strict Contract)</b><br/><i>PromptBuilder.swift</i><br/>─────────────────────────────<br/>• Constructs a strict prompt contract enforcing formatted output and intent filtering<br/>• Injects turns and code; instructs model to prefix with YES| for questions or NO for small talk, with 1 summary sentence + bullet points"]:::process
        DROP_CTX -.->|No Code Needed| PROMPT_BUILD
        RG_TRIGGER --> PROMPT_BUILD
        
        KV_WARM -.-> KV_DISK[("💾 <b>Pre-Computed KV Cache File</b><br/><i>butler_project_memory.bin</i><br/>─────────────────────────────<br/>• Persists pre-computed KV attention state for project memory on disk<br/>• Restores model attention state in &lt;20ms via llama_state_load_file, skipping 1.5s prompt evaluation lag")]:::storage
        KV_DISK -.->|Instant loadState Restore| LLM_EVAL["🧠 <b>Local LLM Engine (llama.cpp)</b><br/><i>LocalLLMEngine.swift</i><br/>─────────────────────────────<br/>• Executes multimodal inference 100% locally on Apple Silicon Metal GPU<br/>• Runs quantized Qwen2.5-VL-7B (Q4_K_M GGUF) via llama.cpp for ultra-low latency response generation with zero cloud calls"]:::model
        PROMPT_BUILD --> LLM_EVAL
        
        LLM_EVAL --> STREAM_INSPECT{"🔍 <b>Early Token Inspection (First 20 Chars)</b><br/><i>ResponseGenerator.swift</i><br/>─────────────────────────────<br/>• Inspects early streaming tokens to evaluate conversational intent<br/>• Analyzes the first 20 generated characters from the model stream to detect YES| or NO intent prefixes"}:::process
        
        STREAM_INSPECT -->|Starts with NO| CANCEL_FAST["🛑 <b>Fast Cancellation Exit</b><br/>─────────────────────────────<br/>• Instantly aborts generation when conversational small talk is detected<br/>• Halts generation in 2-3 tokens (&lt;50ms) on NO prefix, saving 100% GPU computation and keeping HUD silent"]:::output
        
        STREAM_INSPECT -->|Starts with YES prefix| CONFIRM_INTENT["✅ <b>Intent Confirmed</b><br/>─────────────────────────────<br/>• Confirms technical question intent and begins emission to the screen<br/>• Strips YES| prefix cleanly and pipes subsequent markdown tokens to the UI stream"]:::output
        
        STREAM_INSPECT -->|Over 20 chars without prefix| CONFIRM_INTENT
    end

    %% -------------------------------------------------------------
    %% LAYER 6: STREAMING & INVISIBLE UI RENDERING
    %% -------------------------------------------------------------
    subgraph "Layer 6: Real-Time Streaming & Invisible Floating HUD"
        CONFIRM_INTENT --> REPETITION{"🔁 <b>Repetition Guard</b><br/><i>RepetitionGuard.swift</i><br/>─────────────────────────────<br/>• Prevents infinite repetitive token loops common in quantized 7B models<br/>• Tracks real-time token n-gram frequencies and automatically halts generation if a repetition loop is detected"}:::process
        
        REPETITION --> STREAM_OUT["💬 <b>Streaming Markdown Tokens</b><br/>─────────────────────────────<br/>• Streams formatted markdown text to the user interface at interactive speed<br/>• Delivers tokens at 30 to 45 tokens/sec formatted as 1 bold summary sentence followed by concise bullet points"]:::output
        
        STREAM_OUT --> UI_VIEW["🖥️ <b>Invisible Floating HUD Window (NSPanel)</b><br/><i>FloatingWindowView.swift</i><br/>─────────────────────────────<br/>• Renders answers in a floating HUD overlay completely undetectable to screen shares<br/>• Built with SwiftUI on @MainActor; sets sharingType = .none to stay 100% invisible to Zoom, Teams, Meet; nonactivating panel never steals IDE focus"]:::input
    end
```

