using GLib;

namespace Logic {
    /*
     * EnvLineKind — the shapes a line in a dotenv file can take.
     */
    public enum EnvLineKind {
        BLANK,
        COMMENT,
        ENTRY,
        RAW
    }

    /*
     * EnvLine — one line of a dotenv file. Lines the editor never touches
     * keep their original text; edited entries are written back from the
     * key and value.
     */
    public class EnvLine : GLib.Object {
        public EnvLineKind kind = EnvLineKind.RAW;
        public string raw = "";
        public string key = "";
        public string value = "";
        public string inlineComment = "";
        public char quote = (char) 0;
        public bool exported = false;
        public bool dirty = false;

        public string render () {
            if (this.kind != EnvLineKind.ENTRY || (!this.dirty && this.raw != "")) {
                return this.raw;
            }
            string prefix = this.exported ? "export " : "";
            return prefix + this.key + "=" +
                EnvDocument.encodeValue (this.value, this.quote) + this.inlineComment;
        }
    }

    /*
     * EnvDocument — reads and writes a dotenv file. Unchanged lines are
     * kept verbatim so comments, ordering, and quoting survive a save.
     */
    public class EnvDocument : GLib.Object {
        public GLib.List<EnvLine> lines = new GLib.List<EnvLine> ();
        private bool trailingNewline = true;

        public static string envPath (string appPath) {
            return appPath + "/.env";
        }

        public static EnvDocument load (string path, out string? error) {
            error = null;
            var document = new EnvDocument ();
            var file = GLib.File.new_for_path (path);
            if (!file.query_exists ()) return document;

            try {
                uint8[] raw;
                string etag;
                file.load_contents (null, out raw, out etag);
                document.parse ((string) raw);
            } catch (Error e) {
                error = e.message;
            }
            return document;
        }

        public bool save (string path, out string? error) {
            error = null;
            this.sortEntries ();

            try {
                var file = GLib.File.new_for_path (path);
                var stream = file.replace (null, false, GLib.FileCreateFlags.NONE, null);
                string text = this.toText ();
                var data = new uint8[text.length];
                for (int i = 0; i < text.length; i++) {
                    data[i] = (uint8) text[i];
                }
                stream.write_all (data, null);
                stream.close (null);

                // Dotenv files commonly hold credentials; keep them private.
                try {
                    file.set_attribute_uint32 ("unix::mode", 384,
                        GLib.FileQueryInfoFlags.NONE, null);
                } catch (Error e) {
                    // Not fatal; the values are saved.
                }
                return true;
            } catch (Error e) {
                error = e.message;
                return false;
            }
        }

        public GLib.List<EnvLine> entries () {
            var result = new GLib.List<EnvLine> ();
            foreach (var line in this.lines) {
                if (line.kind == EnvLineKind.ENTRY) result.append (line);
            }
            return result;
        }

        public int entryCount () {
            int count = 0;
            foreach (var line in this.lines) {
                if (line.kind == EnvLineKind.ENTRY) count++;
            }
            return count;
        }

        public EnvLine? entryFor (string key) {
            foreach (var line in this.lines) {
                if (line.kind == EnvLineKind.ENTRY && line.key == key) {
                    return line;
                }
            }
            return null;
        }

        /*
         * Returns the comment block directly above an entry, with the "#"
         * markers removed. A blank line ends the block.
         */
        public string commentFor (EnvLine line) {
            int end = -1;
            int index = 0;
            foreach (var candidate in this.lines) {
                if (candidate == line) {
                    end = index;
                    break;
                }
                index++;
            }
            if (end < 0) return "";

            int start = end;
            while (start > 0 &&
                   this.lines.nth_data (start - 1).kind == EnvLineKind.COMMENT) {
                start--;
            }

            var text = new StringBuilder ();
            for (int i = start; i < end; i++) {
                string comment = this.lines.nth_data (i).raw.strip ();
                if (comment.has_prefix ("#")) {
                    comment = comment.substring (1).strip ();
                }
                if (comment == "") continue;
                if (text.len > 0) text.append_c (' ');
                text.append (comment);
            }
            return text.str;
        }

        public EnvLine appendEntry (string key, string value) {
            var line = new EnvLine ();
            line.kind = EnvLineKind.ENTRY;
            line.key = key;
            line.value = value;
            line.dirty = true;
            this.lines.append (line);
            this.trailingNewline = true;
            return line;
        }

        public void removeLine (EnvLine line) {
            this.lines.remove (line);
        }

        /*
         * Sorts the entries alphabetically by key. A comment block directly
         * above an entry moves with it; the file's leading comment block
         * stays at the top, and lines after the last entry stay at the
         * bottom.
         */
        public void sortEntries () {
            int headerEnd = 0;
            while (headerEnd < this.lines.length () &&
                   this.lines.nth_data (headerEnd).kind == EnvLineKind.COMMENT) {
                headerEnd++;
            }
            if (headerEnd > 0 && headerEnd < this.lines.length () &&
                this.lines.nth_data (headerEnd).kind == EnvLineKind.BLANK) {
                headerEnd++;
            }

            int blockCount = 0;
            foreach (var line in this.lines) {
                if (line.kind == EnvLineKind.ENTRY) blockCount++;
            }
            if (blockCount == 0) return;

            int[] starts = new int[blockCount];
            int[] ends = new int[blockCount];
            int pendingStart = headerEnd;
            int blockIndex = 0;
            int index = 0;
            foreach (var line in this.lines) {
                if (line.kind == EnvLineKind.ENTRY) {
                    starts[blockIndex] = pendingStart;
                    ends[blockIndex] = index + 1;
                    blockIndex++;
                    pendingStart = index + 1;
                }
                index++;
            }

            int[] order = new int[blockCount];
            for (int i = 0; i < blockCount; i++) order[i] = i;
            for (int i = 1; i < blockCount; i++) {
                int current = order[i];
                string currentKey = this.lines.nth_data (ends[current] - 1).key.up ();
                int j = i - 1;
                while (j >= 0) {
                    string otherKey = this.lines.nth_data (ends[order[j]] - 1).key.up ();
                    if (strcmp (otherKey, currentKey) <= 0) break;
                    order[j + 1] = order[j];
                    j--;
                }
                order[j + 1] = current;
            }

            var sorted = new GLib.List<EnvLine> ();
            for (int i = 0; i < headerEnd; i++) {
                sorted.append (this.lines.nth_data (i));
            }
            foreach (var currentBlock in order) {
                for (int i = starts[currentBlock]; i < ends[currentBlock]; i++) {
                    sorted.append (this.lines.nth_data (i));
                }
            }
            for (int i = pendingStart; i < (int) this.lines.length (); i++) {
                sorted.append (this.lines.nth_data (i));
            }
            this.lines = (owned) sorted;
        }

        public string toText () {
            var text = new StringBuilder ();
            bool first = true;
            foreach (var line in this.lines) {
                if (!first) text.append_c ('\n');
                text.append (line.render ());
                first = false;
            }
            if (!first && this.trailingNewline) text.append_c ('\n');
            return text.str;
        }

        public static bool isValidKey (string key) {
            if (key == "") return false;
            char first = key[0];
            if (!((first >= 'A' && first <= 'Z') ||
                  (first >= 'a' && first <= 'z') ||
                  first == '_')) {
                return false;
            }
            for (int i = 1; i < key.length; i++) {
                char ch = key[i];
                if ((ch >= 'A' && ch <= 'Z') ||
                    (ch >= 'a' && ch <= 'z') ||
                    (ch >= '0' && ch <= '9') ||
                    ch == '_') {
                    continue;
                }
                return false;
            }
            return true;
        }

        public static bool isSecretKey (string key) {
            string upper = key.up ();
            string[] markers = {
                "KEY", "TOKEN", "SECRET", "PASSWORD", "PASSWD", "CREDENTIAL"
            };
            foreach (var marker in markers) {
                if (upper.contains (marker)) return true;
            }
            return false;
        }

        /*
         * Writes a value back into the file. The original quote style is
         * kept; unquoted values only gain quotes when they would otherwise
         * parse differently.
         */
        public static string encodeValue (string value, char quote) {
            if (quote == '\'' && !value.contains ("'")) {
                return "'" + value + "'";
            }
            if (quote == '"' || quote == '\'' || EnvDocument.needsQuotes (value)) {
                return "\"" + EnvDocument.escapeDouble (value) + "\"";
            }
            return value;
        }

        private static bool needsQuotes (string value) {
            if (value == "" || value != value.strip ()) return true;
            for (int i = 0; i < value.length; i++) {
                char ch = value[i];
                if (ch == '#' || ch == '"' || ch == '\'' || ch == '\\') return true;
            }
            return false;
        }

        private static string escapeDouble (string value) {
            var escaped = new StringBuilder ();
            for (int i = 0; i < value.length; i++) {
                if (value[i] == '\\' || value[i] == '"') escaped.append_c ('\\');
                escaped.append_c (value[i]);
            }
            return escaped.str;
        }

        private void parse (string text) {
            this.lines = new GLib.List<EnvLine> ();
            this.trailingNewline = text.has_suffix ("\n");
            string body = this.trailingNewline
                ? text.substring (0, text.length - 1) : text;
            if (body == "") {
                if (text != "") {
                    var blank = new EnvLine ();
                    blank.kind = EnvLineKind.BLANK;
                    this.lines.append (blank);
                }
                return;
            }
            foreach (var rawLine in body.split ("\n")) {
                this.lines.append (EnvDocument.parseLine (rawLine));
            }
        }

        private static EnvLine parseLine (string rawLine) {
            var line = new EnvLine ();
            line.raw = rawLine;
            string trimmed = rawLine.strip ();

            if (trimmed == "") {
                line.kind = EnvLineKind.BLANK;
                return line;
            }
            if (trimmed.has_prefix ("#")) {
                line.kind = EnvLineKind.COMMENT;
                return line;
            }

            int equals = rawLine.index_of ("=");
            if (equals <= 0) {
                line.kind = EnvLineKind.RAW;
                return line;
            }

            string name = rawLine.substring (0, equals).strip ();
            bool exported = false;
            if (name.has_prefix ("export ")) {
                exported = true;
                name = name.substring (7).strip ();
            }
            if (!EnvDocument.isValidKey (name)) {
                line.kind = EnvLineKind.RAW;
                return line;
            }

            string value;
            char quote;
            string inlineComment;
            EnvDocument.decodeValue (rawLine.substring (equals + 1),
                out value, out quote, out inlineComment);

            line.kind = EnvLineKind.ENTRY;
            line.key = name;
            line.value = value;
            line.quote = quote;
            line.inlineComment = inlineComment;
            line.exported = exported;
            return line;
        }

        private static void decodeValue (string text, out string value,
                                         out char quote, out string inlineComment) {
            quote = (char) 0;
            inlineComment = "";

            int start = 0;
            while (start < text.length &&
                   (text[start] == ' ' || text[start] == '\t')) {
                start++;
            }
            value = text.substring (start);

            if (value.length >= 2) {
                char first = value[0];
                char last = value[value.length - 1];
                if ((first == '"' || first == '\'') && last == first) {
                    quote = first;
                    string inner = value.substring (1, value.length - 2);
                    if (first == '"') {
                        var decoded = new StringBuilder ();
                        int i = 0;
                        while (i < inner.length) {
                            if (inner[i] == '\\' && i + 1 < inner.length) {
                                char next = inner[i + 1];
                                if (next == '"' || next == '\\') {
                                    decoded.append_c (next);
                                    i += 2;
                                    continue;
                                }
                            }
                            decoded.append_c (inner[i]);
                            i++;
                        }
                        inner = decoded.str;
                    }
                    value = inner;
                    return;
                }
            }

            // An unquoted value ends where whitespace is followed by '#'.
            for (int i = 0; i < value.length; i++) {
                if (value[i] == '#' && i > 0 &&
                    (value[i - 1] == ' ' || value[i - 1] == '\t')) {
                    inlineComment = value.substring (i - 1);
                    value = value.substring (0, i - 1);
                    break;
                }
            }
            value = value.strip ();
        }
    }
}
