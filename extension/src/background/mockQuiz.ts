// =============================================================================
// background/mockQuiz.ts — /quiz mock 응답 생성 (Stream C, T=3 §T3.4)
//
// VITE_MOCK_QUIZ=true일 때 sendQuizRequest가 실제 fetch 대신 이 함수를 사용.
// B의 ui/mock.ts처럼 정적 anchorText를 쓰지 않고, 실제로 들어온 body(문단을
// '\n\n'으로 이어붙인 것, A §2.2 규약)에서 anchorText를 뽑아 생성한다.
// → 어떤 데모 기사로 열어도 anchor.ts가 실제 문단과 매칭에 성공한다.
// =============================================================================

import type { Quiz } from '../shared/types'

function splitParagraphs(body: string): string[] {
  return body
    .split('\n\n')
    .map((p) => p.trim())
    .filter((p) => p.length > 0)
}

/** paragraphs.length에 안전하게 clamp된 인덱스. */
function pickIndex(paragraphCount: number, ratio: number): number {
  return Math.min(paragraphCount - 1, Math.max(0, Math.floor(paragraphCount * ratio)))
}

/** anchorText 규약(40~60자, shared_contract.md)에 맞춰 앞부분을 자른다. */
function toAnchorText(paragraph: string): string {
  return paragraph.slice(0, 50)
}

/**
 * 실제 body에서 두 문단을 골라 mock Quiz[]를 만든다.
 * - 첫 번째: 2단계 재질문까지 있는 트리 (재질문 UI 배선 검증용)
 * - 두 번째: 재질문 없는 단순 트리
 */
export function buildMockQuizzes(body: string): Quiz[] {
  const paragraphs = splitParagraphs(body)
  if (paragraphs.length === 0) return []

  const idxA = pickIndex(paragraphs.length, 0.2)
  let idxB = pickIndex(paragraphs.length, 0.6)
  if (idxB === idxA) idxB = Math.min(paragraphs.length - 1, idxA + 1)

  const quizzes: Quiz[] = [
    {
      claimId: 'mock-c1',
      conceptTag: '(mock) 핵심 개념 1',
      anchorText: toAnchorText(paragraphs[idxA]),
      paragraphIndex: idxA,
      question: '(mock) 이 문단이 다루는 핵심 주장을 제대로 이해했는지 확인하는 질문입니다.',
      options: ['(mock) 보기 A', '(mock) 보기 B', '(mock) 보기 C', '(mock) 보기 D'],
      answerIndex: 0,
      explanation: '(mock) 정답 해설 — 실서버 연동 전 배선 검증용 데이터입니다.',
      followups: [
        {
          level: 1,
          prereqConceptTag: '(mock) 선행 개념 1',
          question: '(mock) 1단계 재질문입니다.',
          options: ['(mock) 보기 A', '(mock) 보기 B', '(mock) 보기 C', '(mock) 보기 D'],
          answerIndex: 1,
          explanation: '(mock) 1단계 재질문 해설입니다.',
          followups: [
            {
              level: 2,
              prereqConceptTag: '(mock) 선행 개념 2',
              question: '(mock) 2단계 재질문입니다.',
              options: ['(mock) 보기 A', '(mock) 보기 B', '(mock) 보기 C', '(mock) 보기 D'],
              answerIndex: 2,
              explanation: '(mock) 2단계 재질문 해설입니다.',
              followups: [],
            },
          ],
        },
      ],
    },
    {
      claimId: 'mock-c2',
      conceptTag: '(mock) 핵심 개념 2',
      anchorText: toAnchorText(paragraphs[idxB]),
      paragraphIndex: idxB,
      question: '(mock) 두 번째 문단에 대한 확인 질문입니다.',
      options: ['(mock) 보기 A', '(mock) 보기 B', '(mock) 보기 C', '(mock) 보기 D'],
      answerIndex: 1,
      explanation: '(mock) 정답 해설입니다.',
      followups: [],
    },
  ]

  return quizzes
}
