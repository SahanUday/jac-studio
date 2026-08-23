import re;

def _get_eol_for_counts(default_eol: int, cr: int, lf: int, crlf: int) -> str {
    total_eol_count = cr + lf + crlf;
    total_cr_count = cr + crlf;
    if total_eol_count == 0 {
        return "\n" if default_eol == 1 else "\r\n";
    }
    if total_cr_count > total_eol_count / 2 {
        return "\r\n";
    }
    return "\n";
}

impl PieceTreeTextBufferFactory._get_eol(default_eol: int) -> str {
    return _get_eol_for_counts(default_eol, self.cr, self.lf, self.crlf);
}

impl PieceTreeTextBufferFactory.create(default_eol: int) -> PieceTreeTextBuffer {
    eol = self._get_eol(default_eol);
    chunks = self.chunks;

    if self.normalize_eol and (
        (eol == "\r\n" and (self.cr > 0 or self.lf > 0))
        or (eol == "\n" and (self.cr > 0 or self.crlf > 0))
    ) {
        i = 0;
        while i < len(chunks) {
            s = re.sub(r"\r\n|\r|\n", eol, chunks[i].buffer);
            new_line_start = create_line_starts(s);
            chunks[i] = StringBuffer(buffer=s, line_starts=new_line_start);
            i += 1;
        }
    }

    return PieceTreeTextBuffer(
        init_chunks=chunks, bom=self.bom, init_eol=eol,
        contains_rtl=self.contains_rtl,
        contains_unusual_line_terminators=self.contains_unusual_line_terminators,
        is_basic_ascii=self.is_basic_ascii, init_eol_normalized=self.normalize_eol
    );
}

impl PieceTreeTextBufferFactory.get_first_line_text(length_limit: int) -> str {
    lines = split_lines(self.chunks[0].buffer[0:length_limit]);
    return lines[0];
}

impl PieceTreeTextBufferBuilder.postinit -> None {
    self.chunks = [];
    self.bom = "";
    self.has_previous_char = False;
    self.previous_char = 0;
    self.cr = 0;
    self.lf = 0;
    self.crlf = 0;
    self.contains_rtl = False;
    self.contains_unusual_line_terminators = False;
    self.is_basic_ascii = True;
}

impl PieceTreeTextBufferBuilder.accept_chunk(chunk: str) -> None {
    if len(chunk) == 0 {
        return;
    }

    if len(self.chunks) == 0 and starts_with_utf8_bom(chunk) {
        self.bom = UTF8_BOM_CHARACTER;
        chunk = chunk[1:];
    }

    if len(chunk) == 0 {
        self._accept_chunk1(chunk, False);
        self.has_previous_char = False;
        self.previous_char = 0;
        return;
    }

    last_char = ord(chunk[-1]);
    if last_char == CARRIAGE_RETURN or (last_char >= 0xD800 and last_char <= 0xDBFF) {
        # last character is \r or a high surrogate => keep it back
        self._accept_chunk1(chunk[0:len(chunk) - 1], False);
        self.has_previous_char = True;
        self.previous_char = last_char;
    } else {
        self._accept_chunk1(chunk, False);
        self.has_previous_char = False;
        self.previous_char = last_char;
    }
}

impl PieceTreeTextBufferBuilder._accept_chunk1(chunk: str, allow_empty_strings: bool) -> None {
    if not allow_empty_strings and len(chunk) == 0 {
        return;
    }

    if self.has_previous_char {
        self._accept_chunk2(chr(self.previous_char) + chunk);
    } else {
        self._accept_chunk2(chunk);
    }
}

impl PieceTreeTextBufferBuilder._accept_chunk2(chunk: str) -> None {
    line_starts = create_line_starts_with_counts(chunk);

    self.chunks.append(StringBuffer(buffer=chunk, line_starts=line_starts.line_starts));
    self.cr += line_starts.cr;
    self.lf += line_starts.lf;
    self.crlf += line_starts.crlf;

    if not line_starts.is_basic_ascii {
        # this chunk contains non basic ASCII characters
        self.is_basic_ascii = False;
        if not self.contains_rtl {
            self.contains_rtl = text_contains_rtl(chunk);
        }
        if not self.contains_unusual_line_terminators {
            self.contains_unusual_line_terminators = text_contains_unusual_line_terminators(chunk);
        }
    }
}

impl PieceTreeTextBufferBuilder.finish(normalize_eol: bool = True) -> PieceTreeTextBufferFactory {
    self._finish();
    return PieceTreeTextBufferFactory(
        chunks=self.chunks, bom=self.bom, cr=self.cr, lf=self.lf, crlf=self.crlf,
        contains_rtl=self.contains_rtl,
        contains_unusual_line_terminators=self.contains_unusual_line_terminators,
        is_basic_ascii=self.is_basic_ascii, normalize_eol=normalize_eol
    );
}

impl PieceTreeTextBufferBuilder._finish -> None {
    if len(self.chunks) == 0 {
        self._accept_chunk1("", True);
    }

    if self.has_previous_char {
        self.has_previous_char = False;
        # recreate last chunk
        last_chunk = self.chunks[-1];
        last_chunk.buffer += chr(self.previous_char);
        new_line_starts = create_line_starts(last_chunk.buffer);
        last_chunk.line_starts = new_line_starts;
        if self.previous_char == CARRIAGE_RETURN {
            self.cr += 1;
        }
    }
}
