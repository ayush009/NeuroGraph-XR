"""Builds the app's course data from the lesson files in _slides/course/L*.json.

Writes:
  data/aie_course.json   chapters -> lessons -> cards, quiz, lab ids
  data/aie_graph.json    knowledge graph: nodes (cards + concept nodes), edges, categories
Run:  python tools/build_course.py
"""
import json, os, re, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "_slides", "course")

# (number, chapter title, colour, short category name used in the graph legend)
CHAPTERS = [
    (1, "Introduction & AI Engineering", "#3fa7ff", "Intro"),
    (2, "From Text to Tokens and Back", "#35d6a0", "Tokens"),
    (3, "Foundations of LLMs", "#ff8a3d", "LLM Foundations"),
    (4, "Training & Alignment", "#b583ff", "Training"),
    (5, "Inference & Evaluation", "#ff4f79", "Inference"),
    (6, "Prompt Engineering", "#ffd23f", "Prompting"),
    (7, "Retrieval-Augmented Generation", "#2ec4b6", "RAG"),
]


def short_of(num: int) -> str:
    for n, _, _, short in CHAPTERS:
        if n == num:
            return short
    return str(num)


def main():
    lessons = {}
    for f in glob.glob(os.path.join(SRC, "L*.json")):
        d = json.load(open(f, encoding="utf-8"))
        lessons[d["id"]] = d
    chapters = []
    nodes = {}
    edges = []
    quiz = []
    for num, title, colour, short in CHAPTERS:
        ls = []
        for lid in sorted([k for k in lessons if int(k.split(".")[0]) == num], key=lambda s: [int(x) for x in s.split(".")]):
            d = lessons[lid]
            # animated story scenes (one per card) live next to the lessons in _slides/scenes/
            sp = os.path.join(os.path.dirname(SRC), "scenes", "L%s.json" % lid)
            if os.path.exists(sp):
                sc = json.load(open(sp, encoding="utf-8"))
                for card in d["cards"]:
                    if card["id"] in sc:
                        card["scene"] = sc[card["id"]]
            ls.append({"id": d["id"], "title": d["title"], "goal": d["goal"], "cards": d["cards"]})
            for n in d["nodes"]:
                nodes[n["id"]] = {"id": n["id"], "label": n["label"], "desc": n["desc"], "category": short}
            for e in d["edges"]:
                edges.append([e[0], e[1], e[2]])
            for q in d["quiz"]:
                quiz.append({"lesson": lid, "q": q["q"], "answer": q["answer"],
                             "distractors": q["distractors"], "why": q.get("why", "")})
        chapters.append({"n": num, "title": title, "colour": colour, "lessons": ls})
    # every card must be a graph node: add one automatically if a lesson file forgot it
    added = 0
    for c in chapters:
        for l in c["lessons"]:
            for card in l["cards"]:
                if card["id"] not in nodes:
                    text = card.get("text", "")
                    first = text.split(". ")[0].strip()
                    nodes[card["id"]] = {"id": card["id"], "label": card["title"][:28],
                                         "desc": (first[:160] + ".") if first else card["title"],
                                         "category": short_of(c["n"])}
                    added += 1
    print("auto-added nodes for cards that had none:", added)
    course = {"name": "AI Engineering", "chapters": chapters, "quiz": quiz}
    # guided tour / story data, generated from the chapters so the app's tour, "learn next"
    # and "tour" key work for this course too (they need existing node ids)
    story, tour = [], []
    for c in chapters:
        first = c["lessons"][0]
        ids = [card["id"] for card in first["cards"][:3]]
        story.append({"title": "%d.  %s" % (c["n"], c["title"]), "caption": first["goal"],
                      "say": first["goal"], "focus": ids, "min": 7.0})
        tour.append(first["cards"][0]["id"])
    cat_say = {}
    for c in chapters:
        cat_say[short_of(c["n"])] = "Chapter %d, %s. %s" % (c["n"], c["title"], c["lessons"][0]["goal"])
    graph = {"title": "AI Engineering", "nodes": list(nodes.values()), "edges": edges,
             "categories": {short: col for _, _, col, short in CHAPTERS},
             "demo": {
                 "welcome_caption": "A complete AI engineering course: from a token to a running AI system.",
                 "welcome_say": "Welcome to the AI Engineering course. In this tour you will travel from raw text to tokens, through attention and training, all the way to retrieval and prompt engineering.",
                 "focus_node": tour[1], "hop_start": tour[0], "path_from": tour[0], "path_to": tour[-1],
                 "question": "How does retrieval augmented generation reduce hallucination?",
                 "tour": tour, "tour_end": "That was the AI Engineering course overview. Each chapter is a full lesson with cards, labs and a quiz.",
                 "summary": "Tokens, embeddings, attention, transformers, KV cache, mixture of experts, training and alignment, decoding, evaluation, prompting and RAG.",
                 "chips": ["What is byte pair encoding?", "How does self-attention work?",
                           "Why does a KV cache save compute?", "What is the difference between dense and sparse retrieval?"],
                 "unknown_hint": "Try terms like: tokenizer, attention, KV cache, mixture of experts, RAG, fine-tuning.",
                 "category_say": cat_say, "story": story}}
    json.dump(course, open(os.path.join(ROOT, "data", "aie_course.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    json.dump(graph, open(os.path.join(ROOT, "data", "aie_graph.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    cards = sum(len(l["cards"]) for c in chapters for l in c["lessons"])
    print("chapters=%d lessons=%d cards=%d quiz=%d nodes=%d edges=%d" % (
        len(chapters), sum(len(c["lessons"]) for c in chapters), cards, len(quiz), len(nodes), len(edges)))


if __name__ == "__main__":
    main()
