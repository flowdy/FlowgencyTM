$(function () {
   var ftm = $('#logo').data('FlowgencyTM'), te = $('.taskeditor');
   ftm.dynamize_taskeditor(te);
   ftm.get(te.data('taskid')).archived_because = null;
});
