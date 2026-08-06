from pathlib import Path

_original_read_text = Path.read_text
_original_write_text = Path.write_text


def _read_text(self, encoding=None, errors=None, newline=None):
    with self.open(mode="r", encoding=encoding, errors=errors, newline=newline) as handle:
        return handle.read()


def _write_text(self, data, encoding=None, errors=None, newline=None):
    with self.open(mode="w", encoding=encoding, errors=errors, newline=newline) as handle:
        return handle.write(data)


Path.read_text = _read_text
Path.write_text = _write_text

script_path = Path("tool/apply_favorite_audit_fix.py")
source = _original_read_text(script_path, encoding="utf-8")
exec(compile(source, str(script_path), "exec"), {"__name__": "__main__", "__file__": str(script_path)})
Path("tool/run_favorite_audit_fix.py").unlink()
