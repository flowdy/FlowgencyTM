use strict;

sub parse {
    my ($text, %opts) = @_;
    
    if ( my $add = $opts{incr_heading_level} ) {
        my $h = '#' x $add;
        $text =~ s{ ^ (\#+) }{$h.$1}egxms;
        $text =~ s{ ^ ([^\n]+) \n ([=-])\2+ }
                  { $h .( $2 eq '-' ? '##' : '#' ).' '.$1 }egxms;
    }

    use Text::Markdown;
    return Text::Markdown::Markdown($text);
}

print parse(<<END_MD, incr_heading_level => 3 );
Dies ist eine Überschrift ersten Grades
=======================================

Dies eine zweiten Grades
---------------------------------------

# Dies ist noch eine ersten Grades

## Und dies eine weitere zweiten Grades

### Hier eine dritten Grades

Und hier etwas Text. Er enthält einen Link: <http://www.google.de>

END_MD
