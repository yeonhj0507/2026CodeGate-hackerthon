"""OX 퀴즈 부착 규칙 (DB·LLM 불필요).

LLM 이 만들지 않고 진단 결과에서 기계적으로 뽑으므로 규칙을 여기서 못 박는다.
"""

from app.domain.schemas import Graph
from app.domain.thoughtmap.merge import ScrapInput, merge

URL = "https://news.example.com/rate"


def scrap(**over) -> ScrapInput:
    result = {
        "conceptTag": "기준금리",
        "parentConcept": None,
        "level": 0,
        "correct": False,
        "question": "금리를 내리면 물가가 다시 오를 수 있는 이유는?",
        "selectedOption": "금리 인하는 곧바로 임금을 올려 물가를 자극한다",
        "correctOption": "원화 약세로 수입물가가 올라 국내 물가를 밀어올린다",
    }
    result.update(over)
    return ScrapInput(article_url=URL, article_title="금리 기사", results=[result])


def test_wrong_answer_becomes_false_statement():
    """사용자가 골랐던 오답 선지가 그대로 진술문이 되고, 정답은 X 다."""
    node = merge(Graph(), [scrap()]).nodes[0]

    assert node.oxQuiz is not None
    assert node.oxQuiz.statement == "금리 인하는 곧바로 임금을 올려 물가를 자극한다"
    assert node.oxQuiz.answer is False
    assert node.oxQuiz.sourceQuestion.startswith("금리를 내리면")


def test_correct_answer_becomes_true_statement():
    """맞힌 문항이면 정답 선지로 O 문항을 만든다."""
    node = merge(Graph(), [scrap(correct=True)]).nodes[0]

    assert node.oxQuiz.answer is True
    assert node.oxQuiz.statement == "원화 약세로 수입물가가 올라 국내 물가를 밀어올린다"


def test_no_material_leaves_it_empty():
    """구버전 익스텐션은 선지를 보내지 않는다 — OX 없이 두고 깨지지 않아야 한다."""
    node = merge(
        Graph(),
        [scrap(question=None, selectedOption=None, correctOption=None)],
    ).nodes[0]

    assert node.oxQuiz is None


def test_existing_quiz_is_not_overwritten():
    """재동기화마다 문항이 바뀌면 "아까 그 문제"를 다시 볼 수 없다."""
    first = merge(Graph(), [scrap()])
    assert first.nodes[0].oxQuiz.statement.startswith("금리 인하는")

    second = merge(
        first,
        [scrap(selectedOption="완전히 다른 오답", correctOption="다른 정답")],
    )
    assert second.nodes[0].oxQuiz.statement.startswith("금리 인하는")
