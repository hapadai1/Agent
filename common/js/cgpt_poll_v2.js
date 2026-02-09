// cgpt_poll_v2.js - ChatGPT completion detector
// Returns: JSON { status, reason, hasText, turnIndex }
// status: WAIT | COMPLETED | ERROR

(function(){
  function visible(el) {
    return !!(el && el.getClientRects && el.getClientRects().length);
  }
  function qs(sel, root) {
    return (root || document).querySelector(sel);
  }
  function qsa(sel, root) {
    return Array.from((root || document).querySelectorAll(sel));
  }
  function findStopButton() {
    var a = qs('button[data-testid="stop-button"]');
    if (visible(a)) return a;
    var b = qsa('button[aria-label*="Stop"]').find(visible);
    return b || null;
  }
  function getTurns() {
    return qsa('article[data-testid^="conversation-turn"]');
  }
  function findResponseTurn(turns) {
    if (turns.length === 0) return null;
    var searchCount = Math.min(3, turns.length);
    for (var i = turns.length - 1; i >= turns.length - searchCount; i--) {
      var turn = turns[i];
      if (qs('.markdown', turn)) return { turn: turn, index: i };
      if (qs('button[data-testid="copy-turn-action-button"]', turn)) return { turn: turn, index: i };
      if (qs('button[data-testid="good-response-turn-action-button"]', turn)) return { turn: turn, index: i };
      if (qs('button[data-testid="bad-response-turn-action-button"]', turn)) return { turn: turn, index: i };
    }
    return { turn: turns[turns.length - 1], index: turns.length - 1 };
  }
  function hasActionButtons(turn) {
    if (!turn) return false;
    var ids = ['copy-turn-action-button','good-response-turn-action-button','bad-response-turn-action-button'];
    for (var i = 0; i < ids.length; i++) {
      var btn = qs('button[data-testid="' + ids[i] + '"]', turn);
      if (visible(btn)) return true;
    }
    var btns = qsa('button,[role="button"]', turn);
    return btns.some(function(b) {
      if (!visible(b)) return false;
      var label = (b.getAttribute('aria-label') || b.getAttribute('title') || b.innerText || '').trim();
      return /copy|like|dislike/i.test(label);
    });
  }
  function hasText(turn) {
    if (!turn) return false;
    var md = qs('.markdown', turn);
    if (md) {
      var text = (md.innerText || '').trim();
      return text.length >= 20;  // 최소 20자 이상이어야 진짜 텍스트로 인정
    }
    return false;
  }
  function detectError() {
    var body = document.body ? document.body.innerText : '';
    if (/Something went wrong|Try again/i.test(body)) return 'error_page';
    if (/Sign in|Log in/i.test(body) && !qs('article[data-testid^="conversation-turn"]')) return 'login_required';
    // 스트리밍 중지 상태 감지 (한글/영문)
    if (/스트리밍이 중지되었습니다|Streaming has stopped|Streaming stopped/i.test(body)) return 'streaming_stalled';
    return null;
  }
  var errorReason = detectError();
  if (errorReason) {
    return JSON.stringify({status:'ERROR',reason:errorReason,hasText:false,turnIndex:-1});
  }
  var stopBtn = findStopButton();
  if (stopBtn) {
    return JSON.stringify({status:'WAIT',reason:'streaming',hasText:false,turnIndex:-1});
  }
  var turns = getTurns();
  var result = findResponseTurn(turns);
  if (!result || !result.turn) {
    return JSON.stringify({status:'WAIT',reason:'wait_turn',hasText:false,turnIndex:-1});
  }
  var turn = result.turn;
  var turnIndex = result.index;
  var textExists = hasText(turn);
  var actionsExist = hasActionButtons(turn);
  // COMPLETED: 액션버튼 + 텍스트(20자 이상) 둘 다 있어야 함
  if (actionsExist && textExists) {
    return JSON.stringify({status:'COMPLETED',reason:'completed',hasText:true,turnIndex:turnIndex});
  }
  // 액션은 있는데 텍스트 없음 → 아직 대기
  if (actionsExist && !textExists) {
    return JSON.stringify({status:'WAIT',reason:'no_text_yet',hasText:false,turnIndex:turnIndex});
  }
  // 텍스트는 있는데 액션 없음 → 완료 근접
  if (textExists && !actionsExist) {
    return JSON.stringify({status:'WAIT',reason:'no_actions_yet',hasText:true,turnIndex:turnIndex});
  }
  return JSON.stringify({status:'WAIT',reason:'unknown_wait',hasText:false,turnIndex:turnIndex});
})();
