struct IndexSchema {
    static let version = 2   // bumped: wipes indexes that contain vendored llama.cpp/whisper.cpp code
    
    static let sqlCommands = [
        "CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);",
        """
        CREATE TABLE IF NOT EXISTS projects(
          id TEXT PRIMARY KEY,
          root_path TEXT NOT NULL, name TEXT, indexed_at REAL);
        """,
        """
        CREATE TABLE IF NOT EXISTS files(
          id INTEGER PRIMARY KEY,
          project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
          rel_path TEXT NOT NULL, language TEXT, size INTEGER NOT NULL, mtime REAL NOT NULL,
          content_hash TEXT NOT NULL, is_test INTEGER NOT NULL DEFAULT 0, indexed_at REAL,
          UNIQUE(project_id, rel_path));
        """,
        """
        CREATE TABLE IF NOT EXISTS symbols(
          id INTEGER PRIMARY KEY,
          project_id TEXT NOT NULL,
          file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
          name TEXT NOT NULL, name_norm TEXT NOT NULL,
          qualified TEXT NOT NULL, kind TEXT NOT NULL, parent TEXT,
          start_line INTEGER NOT NULL, end_line INTEGER NOT NULL);
        """,
        "CREATE INDEX IF NOT EXISTS symbols_norm ON symbols(project_id, name_norm);",
        """
        CREATE TABLE IF NOT EXISTS chunks(
          id INTEGER PRIMARY KEY,
          project_id TEXT NOT NULL,
          file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
          symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL,
          chunk_index INTEGER NOT NULL, start_line INTEGER NOT NULL, end_line INTEGER NOT NULL,
          content TEXT NOT NULL, content_hash TEXT NOT NULL, token_est INTEGER NOT NULL);
        """,
        "CREATE INDEX IF NOT EXISTS chunks_file ON chunks(file_id);",
        """
        CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
          symbol, path, words, content, tokenize = 'unicode61 remove_diacritics 2');
        """,
        """
        CREATE TABLE IF NOT EXISTS refs(
          src_chunk_id INTEGER NOT NULL REFERENCES chunks(id) ON DELETE CASCADE,
          target_symbol_id INTEGER NOT NULL REFERENCES symbols(id) ON DELETE CASCADE,
          PRIMARY KEY(src_chunk_id, target_symbol_id));
        """,
        """
        CREATE TABLE IF NOT EXISTS chunk_embeddings(
          chunk_id INTEGER PRIMARY KEY REFERENCES chunks(id) ON DELETE CASCADE,
          model TEXT NOT NULL, dim INTEGER NOT NULL, vec BLOB NOT NULL);
        """
    ]
}
