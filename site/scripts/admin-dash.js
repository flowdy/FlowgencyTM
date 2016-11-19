$(function () {
    $(".buttons").controlgroup().next("td").find("a").button();

    $("table").on('click', '.sendmail', function () {
        var action = $(this).text().replace(/\s/g, ''),
            tr = $(this).closest("tr"),
            mailtext = $("#mail-" + action).text()
                .replace(/\bNAME\b/, tr.find(".name").text())
                .replace(/\bLINK\b/, window.location.origin
                                   + tr.find(".login-link").attr("href")
                 ),
            mailto = $(this).closest("tr").find(".email a").attr("href")
            + '?subject=Your ' + action + ' request for '
                + window.location.host
            + '&body=' + encodeURIComponent( mailtext )
            ;

        window.location.href = mailto;

    });
   
});
