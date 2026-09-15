#!/usr/bin/env python3
"""Pull courses, assignments, syllabus and every linked file (textbook PDFs
included) from Canvas into library/canvas/, and rebuild library/INDEX.md.

Reads CANVAS_URL and CANVAS_TOKEN from .env in the project folder.
"""
import datetime
import html
import json
import logging
import os
import re
import sys
from pathlib import Path

import requests

logging.getLogger("pypdf").setLevel(logging.ERROR)  # font warnings are harmless noise

# Data folder: passed by the app, or the default ~/Documents/DictateBar.
ROOT = Path(os.environ.get("DICTATEBAR_HOME", Path.home() / "Documents" / "DictateBar"))
LIB = ROOT / "library"
CANVAS_DIR = LIB / "canvas"
DRIVE_DIR = LIB / "drive"


def load_env():
    env_file = ROOT / ".env"
    if not env_file.exists():
        return
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


load_env()
BASE = os.environ.get("CANVAS_URL", "").rstrip("/")
TOKEN = os.environ.get("CANVAS_TOKEN", "")
if not BASE or not TOKEN or "paste-your" in TOKEN:
    sys.exit("CANVAS_URL / CANVAS_TOKEN missing. Edit .env in the project folder.")

session = requests.Session()
session.headers["Authorization"] = f"Bearer {TOKEN}"


def api(path, **params):
    """GET a Canvas endpoint, following pagination for list results."""
    url = f"{BASE}/api/v1{path}"
    params.setdefault("per_page", 100)
    items = []
    while url:
        r = session.get(url, params=params, timeout=60)
        r.raise_for_status()
        params = {}
        data = r.json()
        if not isinstance(data, list):
            return data
        items.extend(data)
        url = r.links.get("next", {}).get("url")
    return items


def html_to_text(fragment):
    if not fragment:
        return ""
    text = re.sub(r"<(br|/p|/div|/li|/h\d|/tr)\s*/?>", "\n", fragment, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n\s*\n+", "\n\n", text)
    return text.strip()


def file_ids_in(fragment):
    return set(re.findall(r"/files/(\d+)", fragment or ""))


def safe_name(name):
    return re.sub(r"[^\w\-. ]+", "", name).strip()[:100] or "untitled"


def extract_pdf_text(pdf_path):
    from pypdf import PdfReader

    try:
        reader = PdfReader(str(pdf_path))
        pages = [page.extract_text() or "" for page in reader.pages]
        return "\n\n".join(f"[page {i + 1}]\n{p}" for i, p in enumerate(pages) if p.strip())
    except Exception as e:  # scanned PDFs, encrypted PDFs
        return f"(could not extract text: {e})"


def download_files(course_dir, file_ids):
    """Download each Canvas file once; re-download only if Canvas says it changed."""
    files_dir = course_dir / "files"
    text_dir = course_dir / "text"
    files_dir.mkdir(exist_ok=True)
    text_dir.mkdir(exist_ok=True)
    index_path = course_dir / ".files.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else {}
    downloaded = []

    for fid in sorted(file_ids):
        try:
            meta = api(f"/files/{fid}")
        except requests.HTTPError:
            continue  # no permission for this file
        name = safe_name(meta.get("display_name") or meta.get("filename") or fid)
        dest = files_dir / name
        stamp = meta.get("updated_at", "")
        if index.get(fid) == stamp and dest.exists():
            downloaded.append(name)
            continue
        with session.get(meta["url"], stream=True, timeout=300) as r:
            r.raise_for_status()
            with open(dest, "wb") as f:
                for chunk in r.iter_content(1 << 16):
                    f.write(chunk)
        if dest.suffix.lower() == ".pdf":
            (text_dir / (dest.stem + ".txt")).write_text(extract_pdf_text(dest))
        index[fid] = stamp
        downloaded.append(name)
        print(f"  downloaded {name}")

    index_path.write_text(json.dumps(index, indent=2))
    return downloaded


CALENDAR = []  # assignments with due dates, for the app's calendar + suggestions


def sync_course(course):
    name = safe_name(course.get("name") or course.get("course_code") or str(course["id"]))
    course_dir = CANVAS_DIR / name
    course_dir.mkdir(parents=True, exist_ok=True)
    print(f"Course: {name}")
    file_ids = set()

    syllabus = html_to_text(course.get("syllabus_body"))
    file_ids |= file_ids_in(course.get("syllabus_body"))
    term = (course.get("term") or {}).get("name", "")
    (course_dir / "course.md").write_text(
        f"# {course.get('name', name)}\n\nCourse code: {course.get('course_code', '')}\n"
        f"Term: {term}\nCanvas id: {course['id']}\n\n## Syllabus\n\n{syllabus or '(none posted)'}\n"
    )

    # "submission" gives us this student's own score and turned-in state, which is
    # what the dashboard needs to show missing work and grades.
    assignments = api(f"/courses/{course['id']}/assignments", **{"include[]": ["rubric", "submission"]})
    assignments.sort(key=lambda a: a.get("due_at") or "9999")
    lines = [f"# Assignments — {course.get('name', name)}\n"]
    for a in assignments:
        sub = a.get("submission") or {}
        CALENDAR.append({"id": a["id"], "course": name, "name": a.get("name"), "due_at": a.get("due_at"),
                         "points": a.get("points_possible"), "url": a.get("html_url"),
                         "submitted_at": sub.get("submitted_at"),
                         "score": sub.get("score"),
                         "grade": sub.get("grade"),
                         "state": sub.get("workflow_state"),      # unsubmitted | submitted | graded
                         "missing": bool(sub.get("missing")),
                         "late": bool(sub.get("late"))})
        due = (a.get("due_at") or "no due date").replace("T", " ").rstrip("Z")
        lines.append(f"\n## {a.get('name')}\n\nDue: {due}\nPoints: {a.get('points_possible')}\n")
        lines.append(html_to_text(a.get("description")) or "(no description)")
        if a.get("rubric"):
            lines.append("\nRubric:")
            for crit in a["rubric"]:
                lines.append(f"- {crit.get('description')} ({crit.get('points')} pts): {html_to_text(crit.get('long_description'))}")
        file_ids |= file_ids_in(a.get("description"))
    (course_dir / "assignments.md").write_text("\n".join(lines) + "\n")

    modules = api(f"/courses/{course['id']}/modules", **{"include[]": ["items"]})
    mod_lines = [f"# Modules — {course.get('name', name)}\n"]
    for m in modules:
        mod_lines.append(f"\n## {m.get('name')}\n")
        for item in m.get("items") or []:
            mod_lines.append(f"- [{item.get('type')}] {item.get('title')}")
            if item.get("type") == "File" and item.get("content_id"):
                file_ids.add(str(item["content_id"]))
            elif item.get("type") == "Page" and item.get("page_url"):
                try:
                    page = api(f"/courses/{course['id']}/pages/{item['page_url']}")
                    file_ids |= file_ids_in(page.get("body"))
                    (course_dir / "pages").mkdir(exist_ok=True)
                    (course_dir / "pages" / (safe_name(item["title"]) + ".md")).write_text(
                        f"# {item['title']}\n\n{html_to_text(page.get('body'))}\n")
                except requests.HTTPError:
                    pass
    (course_dir / "modules.md").write_text("\n".join(mod_lines) + "\n")

    files = download_files(course_dir, file_ids)
    return name, len(assignments), files


def course_grade(course):
    """The running grade Canvas shows for this course, if the teacher publishes it."""
    name = safe_name(course.get("name") or course.get("course_code") or str(course["id"]))
    enrollments = [e for e in (course.get("enrollments") or []) if e.get("type") == "student"]
    enrollment = enrollments[0] if enrollments else {}
    return {"course": name,
            "display": course.get("name") or name,
            "teacher": (course.get("course_code") or "").split(" - ")[-1],
            "score": enrollment.get("computed_current_score"),
            "letter": enrollment.get("computed_current_grade")}


def write_index(courses):
    lines = ["# Library index (auto-generated by sync_canvas.py)\n",
             "Read this first. Each course folder has course.md (syllabus), assignments.md, modules.md,",
             "pages/ (module pages), files/ (originals) and text/ (searchable text of PDFs).\n",
             "## Canvas courses\n"]
    for name, n_assign, files in courses:
        lines.append(f"### canvas/{name}\n- {n_assign} assignments")
        for f in files:
            lines.append(f"- files/{f}")
        lines.append("")
    lines.append("## Recorded classes (classes/<course>/)\n")
    classes_dir = LIB / "classes"
    class_files = sorted(classes_dir.rglob("*.notes.md")) if classes_dir.exists() else []
    if class_files:
        lines.append("Each *.notes.md is organized notes from one recorded class; the matching *.transcript.txt is the raw transcript.")
        lines += [f"- {p.relative_to(LIB)}" for p in class_files]
    else:
        lines.append("(none yet - record a class with Option+C)")
    lines.append("")
    lines.append("## Google Drive exports (drive/)\n")
    drive_files = [p for p in DRIVE_DIR.rglob("*") if p.is_file() and not p.name.startswith(".")]
    if drive_files:
        lines += [f"- {p.relative_to(LIB)}" for p in sorted(drive_files)]
    else:
        lines.append("(empty — drop Google Drive exports into library/drive/)")
    (LIB / "INDEX.md").write_text("\n".join(lines) + "\n")


def main():
    CANVAS_DIR.mkdir(parents=True, exist_ok=True)
    DRIVE_DIR.mkdir(parents=True, exist_ok=True)
    # "total_scores" adds the running grade for each course to its enrollment record.
    courses = api("/courses", **{"enrollment_state": "active",
                                 "include[]": ["syllabus_body", "term", "total_scores"]})
    results = []
    grades = []
    for course in courses:
        if not course.get("name"):
            continue  # restricted / unpublished course stubs
        try:
            results.append(sync_course(course))
            grades.append(course_grade(course))
        except Exception as e:
            print(f"  skipped {course.get('name')}: {e}", file=sys.stderr)
    write_index(results)
    (LIB / "calendar.json").write_text(json.dumps(CALENDAR, indent=2))
    (LIB / "grades.json").write_text(json.dumps(grades, indent=2))
    (LIB / ".last_sync").write_text(datetime.datetime.now().isoformat())
    print(f"Synced {len(results)} courses.")


if __name__ == "__main__":
    main()
