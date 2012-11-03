use strict;
use Benchmark 'cmpthese';
use Bit::Vector;

# Länge % 8 == 0 trifft nicht immer zu, hier aber der Einfachkeit halber ang.
my $length = 1_000_000; 

# $data, mit vec() zu verarbeiten
my $data = '';
$data .= pack('C', int rand(256)) for 1..$length/8;

# Das Bitmuster hat direkt Einfluss darauf, wie oft ein neuer Wert an @cache
# angehängt und wie oft $cache[-1] erhöht bzw. verringert wird.
# Wir kennen es nicht, da es durch den Nutzer (mittelbar) festgelegt wird.
# Die von rand erzeugte 0<>1-Wechselfrequenz ist eigentlich viel zu groß,
# aber wollen wir uns mal nicht verkünsteln ...
my @array = split '', unpack 'B*', $data;

# Vorschlag von topeg++. Der Umweg über $bin_data ist mE unnötig.
# Zwar bräuchte das ähnlich wenig Speicher wie ein Bitvektor, aber da er bei
# jedem Funktionsaufruf neu aufgeblasen werden muss, nützt uns das nicht viel.
# So sparen wir uns wenigstens die Verwaltungsinformationen des Arrays und
# von 999.999 Skalaren
my $str_data = join '', @array;

my $vec = Bit::Vector->new_Bin(1_000_000, $str_data);

# Vorschlag von raubtier++: GeXOR'ter Kovektor
my $vex = $vec->Clone;
$vex->shift_left(!$vec->lsb);
$vex->ExclusiveOr($vex,$vec);

# Perl optimiert nicht für Methodenaufrufe (s. Benchmark unten) 
# Daher müssen wir das machen:
*test = $vec->can('bit_test'); 

# Die XOR-Weiche bleibe hier unberuecksichtigt
# Der gesuchte Kompromiss kann sie gerne beinhalten
my ($start,$end) = (0,999_999);
cmpthese(100, {

    # über Array-Slice iterieren:
    slice => sub {
                 my (@cache, $last);
                 for (@array[$start..$end]) {
                     if ($_ xor $last // !$_) { push @cache, $_ ? 1 : -1 }
                     else { $cache[-1] += $_ }
                     $last = $_;
                 }
             },

    index => sub {
                 my (@cache,$last,$v);
                 for ( my $i = $start; $i <= $end; $i++ ) {
                     $v = $array[$i];
                     if ($v xor $last // !$v) { push @cache, $v ? 1 : -1 }
                     else { $cache[-1] += $v }
                     $last = $v;
                 }
             },

    # vorher in ein eigenes Array kopieren, denn darüber wird schneller iteriert:                   
    array => sub {
                 my @array = @array[$start .. $end];
                 my (@cache,$last);
                 for ( @array ) {
                     if ($_ xor $last // !$_) { push @cache, $_ ? 1 : -1 }
                     else { $cache[-1] += $_ }
                     $last = $_;
                 }
             },

    # Müssten wir stets über das ganze @array laufen, gäbs also weder @start noch @end:
    theor => sub {
                 # my @array = @array[$start .. $end];
                 my (@cache, $last);
                 for (@array) {
                     if ($_ xor $last // !$_) { push @cache, $_ ? 1 : -1 }
                     else { $cache[-1] += $_ }
                     $last = $_;
                 }
             },

    # Subroutinenaufruf an Bit::Vector, d.h. gecachter Methodenaufruf:
    bitvr => sub {
                 my (@cache, $last, $v);
                 for ( my $i = $start; $i <= $end; $i++ ) {
                     $v = test($vec,$i);
                     if ($v xor $last // !$v) { push @cache, $v ? 1 : -1 }
                     else { $cache[-1] += $v }
                     $last = $v;
                 }
             },

    # ungecacht:
    bitvm => sub {
                 my (@cache, $last, $v);
                 for ( my $i = $start; $i <= $end; $i++ ) {
                     $v = $vec->bit_test($i);
                     if ($v xor $last // !$v) { push @cache, $v ? 1 : -1 }
                     else { $cache[-1] += $v }
                     $last = $v;
                 }
             },

    # Test gegen XOR'd Covektor, Vorschlag von raubtier++ ($vex-Init. oben):
    bitvx => sub {
                 my (@cache, $last, $v);
                 for ( my $i = $start; $i <= $end; $i++ ) {
                     $v = test($vec,$i);
                     if (test($vex,$i)) { push @cache, $v ? 1 : -1 }
                     else { $cache[-1] += $v }
                 }
             },

    # Sparen wir uns die Strukturdaten des Arrays und von 999.999 Skalaren
    # Vorschlag von topeg++, angeglichen. $bit_data-Initialisierung oben.
    strng => sub {
                 my (@cache, $last, $v);
                 for ( my $i = $start; $i <= $end; $i++ ) {
                     $v = substr($str_data,$_,1);
                     if ($v ne $last || $v eq '0') {
                         push @cache, $v eq '1' ? 1 : -1
                     }
                     else { $cache[-1] += $v } 
                     $last = $v;
                 }   
             },  

    # und schließlich mit unserem Flagschiff, dem vec() ...
    vectr => sub {
                 my ($last,@cache,$v);
                 for ( my $i = $start; $i <= $end; $i++ ) {
                     $v = vec($data,$i,1);
                     if ($v xor $last // !$v) { push @cache, $v ? 1 : -1 }
                     else { $cache[-1] += $v } 
                     $last = $v;
                 }
             },
    }
);

# Dies ist die Ausgabe:
#==============================
