// =============================================================================
// content/ui/QuestionView.tsx — 한 문항의 질문/채점/설명 뷰 (Stream B)
//
// phase === 'ASKING'          → 보기 선택 + 제출
// phase === 'SHOW_EXPLANATION' → 채점된 보기 + 설명 + 다음 액션
//
// selected(선택 인덱스)는 store가 아니라 이 컴포넌트 로컬 상태로 유지한다.
// (SessionStore 계약에 selected가 없으므로 store를 오염시키지 않기 위함.)
// active가 바뀌면 Panel이 key로 remount → selected 자동 초기화.
// =============================================================================

import { useState } from 'react'
import type { ActiveQuestion, SessionStore } from '../../shared/types'
import { MAX_FOLLOWUP_LEVEL } from '../../shared/constants'
import { Explanation } from './Explanation'

const KEYS = ['A', 'B', 'C', 'D', 'E', 'F']

/** active.item이 검사하는 개념명 (chip 표시용). */
function conceptLabel(active: ActiveQuestion): string {
  return active.level === 0
    ? active.quiz.conceptTag
    : (active.item as { prereqConceptTag: string }).prereqConceptTag
}

function levelLabel(level: 0 | 1 | 2): string | null {
  if (level === 0) return null
  return `선행 개념 · ${level}단계`
}

interface Props {
  active: ActiveQuestion
  phase: SessionStore['phase']
  onSubmit: (index: number) => void
  onNext: () => void
}

export function QuestionView({ active, phase, onSubmit, onNext }: Props) {
  const [selected, setSelected] = useState<number | null>(null)
  const { item } = active
  const graded = phase === 'SHOW_EXPLANATION'
  const level = levelLabel(active.level)

  return (
    <div>
      <div className="tags">
        <span className="chip">{conceptLabel(active)}</span>
        {level && <span className="chip level">{level}</span>}
      </div>

      <p className="question">{item.question}</p>

      <div className="options" role="listbox">
        {item.options.map((opt, i) => {
          const isSelected = selected === i
          const isAnswer = i === item.answerIndex
          // 채점 후: 정답은 항상 초록, 사용자가 고른 오답은 빨강.
          let cls = 'option'
          if (graded) {
            if (isAnswer) cls += ' correct'
            else if (isSelected) cls += ' wrong'
          } else if (isSelected) {
            cls += ' selected'
          }
          return (
            <button
              key={i}
              type="button"
              className={cls}
              disabled={graded}
              onClick={() => setSelected(i)}
            >
              <span className="key">{KEYS[i]}</span>
              <span className="label">{opt}</span>
              {graded && isAnswer && <span className="mark">✓</span>}
              {graded && isSelected && !isAnswer && <span className="mark">✕</span>}
            </button>
          )
        })}
      </div>

      {!graded && (
        <button
          type="button"
          className="submit"
          disabled={selected === null}
          onClick={() => selected !== null && onSubmit(selected)}
        >
          제출
        </button>
      )}

      {graded && (
        <Explanation
          text={item.explanation}
          canDescend={item.followups.length > 0 && active.level < MAX_FOLLOWUP_LEVEL}
          onNext={onNext}
        />
      )}
    </div>
  )
}
