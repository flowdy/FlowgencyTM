INFILE="$1.txt"
OUTFILE="$1.html"

{ 
cat <<HEADER
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<title>FlowTime – Grundlagen</title>
HEADER
cat style.css
echo "</head><body>"

markdown $INFILE

echo "</body></html>"
} > $OUTFILE
