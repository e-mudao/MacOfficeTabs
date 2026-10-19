#!/usr/bin/env python3
"""Create ten disposable OOXML fixture documents; no Office automation or dependencies."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
from xml.sax.saxutils import escape
root = Path(__file__).resolve().parents[1] / 'docs/evidence/fixtures'
paths = [root / 'a/same.docx', root / 'b/same.docx'] + [root / f'test-{n:02}.docx' for n in range(3, 11)]
for index, path in enumerate(paths, 1):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        print(f'Kept existing fixture: {path}')
        continue
    with ZipFile(path, 'w', ZIP_DEFLATED) as doc:
        doc.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
        doc.writestr('_rels/.rels', '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
        text = escape(f'MacOfficeTabs disposable fixture {index}. Keyboard test: type here and undo.')
        doc.writestr('word/document.xml', f'<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>{text}</w:t></w:r></w:p><w:sectPr/></w:body></w:document>')
    print(path)
