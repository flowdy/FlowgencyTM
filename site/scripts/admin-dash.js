$(function () {
    $(".buttons").buttonset().next("td").find("a").button();

    $("table").on('click', '.sendmail', function () {
        var action = $(this).text(), tr = $(this).closest("tr"),
            mailtext = $("#mail-" + action).text()
                .replace(/\bNAME\b/, tr.find(".name").text())
                .replace(/\bLINK\b/, tr.find(".login-link").attr("href"))
            ;

        window.location.href
            = $(this).closest("tr").find(".email a").attr("href")
            + '?subject=Your ' + action + ' request for '
                + window.location.host
            + '&body=' + encodeURIComponent( mailtext )
            ;

    });
   
});
