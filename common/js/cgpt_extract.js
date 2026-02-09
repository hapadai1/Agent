// cgpt_extract.js - ChatGPT 텍스트 회수 (설계_2 MVP+)
// 입력: turnIndex (window.__cgpt_turnIndex로 전달)
// 반환: JSON { ok, text, partial, step }
// step: dom | scroll | fallback

(function(){
  var SCROLL_WAIT_MS = 500;  // scrollIntoView 후 대기

  function qs(sel, root) {
    return (root || document).querySelector(sel);
  }

  function qsa(sel, root) {
    return Array.from((root || document).querySelectorAll(sel));
  }

  function getTurns() {
    return qsa('article[data-testid^="conversation-turn"]');
  }

  function cleanText(text) {
    if (!text) return '';
    // 줄바꿈 유지, 각 줄 내 연속 공백만 정리
    return text.split('\n').map(function(line) {
      return line.replace(/[ \t]+/g, ' ').trim();
    }).join('\n').replace(/\n{3,}/g, '\n\n').trim();
  }

  // Step 1: DOM 기반 추출 (.markdown 우선)
  function extractFromDOM(turn) {
    if (!turn) return '';

    // 1. .markdown 우선
    var markdowns = qsa('.markdown', turn);
    if (markdowns.length > 0) {
      var md = markdowns[markdowns.length - 1];
      var text = cleanText(md.innerText || '');
      if (text.length > 0) return text;
    }

    // 2. .markdown 없으면 전체 innerText에서 시도
    var fullText = cleanText(turn.innerText || '');
    return fullText;
  }

  // Step 2: scrollIntoView 후 재추출 (동기 버전 - 대기는 bash에서)
  function scrollAndMark(turn) {
    if (!turn) return false;
    try {
      turn.scrollIntoView({ block: 'center', behavior: 'instant' });
      return true;
    } catch (e) {
      return false;
    }
  }

  // ===== 메인 로직 =====

  var turnIndex = window.__cgpt_turnIndex;
  if (turnIndex === undefined || turnIndex === null || turnIndex < 0) {
    return JSON.stringify({
      ok: false,
      text: '',
      partial: false,
      step: 'error',
      reason: 'invalid_turn_index'
    });
  }

  var turns = getTurns();
  if (turnIndex >= turns.length) {
    return JSON.stringify({
      ok: false,
      text: '',
      partial: false,
      step: 'error',
      reason: 'turn_not_found'
    });
  }

  var turn = turns[turnIndex];

  // Step 1: DOM 추출
  var text = extractFromDOM(turn);
  if (text.length > 0) {
    return JSON.stringify({
      ok: true,
      text: text,
      partial: false,
      step: 'dom'
    });
  }

  // Step 2가 필요한 경우 scrollIntoView 실행하고 표시
  // (bash에서 SCROLL_WAIT_MS 후 다시 호출)
  var scrollMode = window.__cgpt_scrollMode;
  if (!scrollMode) {
    // 첫 호출: 스크롤 실행하고 retry 요청
    scrollAndMark(turn);
    return JSON.stringify({
      ok: false,
      text: '',
      partial: false,
      step: 'need_scroll_retry',
      reason: 'scrolled_need_retry'
    });
  }

  // scrollMode=true: 스크롤 후 재시도
  text = extractFromDOM(turn);
  if (text.length > 0) {
    return JSON.stringify({
      ok: true,
      text: text,
      partial: false,
      step: 'scroll'
    });
  }

  // Step 3: fallback - turn 전체 innerText라도
  var fallbackText = cleanText(turn.innerText || '');
  if (fallbackText.length > 0) {
    return JSON.stringify({
      ok: true,
      text: fallbackText,
      partial: true,
      step: 'fallback'
    });
  }

  // 실패
  return JSON.stringify({
    ok: false,
    text: '',
    partial: false,
    step: 'failed',
    reason: 'no_text_found'
  });
})();
