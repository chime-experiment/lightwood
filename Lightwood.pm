#!/usr/bin/perl -wT

# ==== SETUP

package Lightwood;
use strict;

use Lightwood::Slack::App;
use Lightwood::Slack::Client qw(:info);
use Lightwood::Wiki;

# Post a thing to the wiki
sub _tpost_run_note {
  local $_;
  my (%params) = @_;

  my $wiki = Lightwood::Wiki->new();

  my @now = localtime time;

  # The text of what we're adding
  my $display_name = display_name($params{user}) || "<$params{user}>";
  my $entry = sprintf "* [%02i:%02i @%s] %s", @now[2,1], $display_name,
  $params{payload};

  my $day = sprintf "%04i-%02i-%02i", $now[5] + 1900, $now[4] + 1, $now[3];
  my @month_name = (qw(January February March April May June July August
    September October November December));
  my $page = "Run Notes - " . $month_name[$now[4]] . " " . ($now[5] + 1900);

  # The message of a parsing error
  my $parse_error = "I'm sorry, I wasn't able to parse the run notes! " .
  ":slightly_frowning_face: If you report this to <\@U5T9JHE48>, include the " .
  "current time with the report.";

  # TEST
  $page = "User:Dvw";

  # get the wikitext
  my $text = $wiki->GetWikiText($page);

  # Run over lines in the text
  my $newtext;
  my $blanks = "";
  my $first = 1;
  my $header = 1;
  my $before = 1;
  for (split /^/, $text) {
    if ($first) {
      # Make sure things are kosher.  This should be the header
      if ($_ ne "{{Run Notes Header}}\n") {
        return $parse_error
      }
      $newtext = $_;
      $first = 0;
    } elsif ($header) {
      # Here we're looking for today's section header
      if ($_ =~ /^== *\{\{Day|$day\}\} *==/) {
        $header = 0;
      }
      $newtext .= $_;
    } elsif ($before) {
      # Now looking for the end of the section
      if ($_ eq "\n") {
        # We collect blank lines here so we don't have to unspool them later
        $blanks .= $_;
        next
      } elsif ($_ =~ /^==[^=]/) {
        # We're at the end of this section.  Add the entry, then a blank,
        # then the current line (i.e. drop all the accumulated blanks)
        $newtext .= $entry . "\n\n" . $_;
        $before = 0;
        next
      }
      # Include all the deferred blank lines
      $newtext .= $blanks . $_;
      $blanks = "";
    } else {
      # We're done; just spool the rest of the text onto the output
      $newtext .= $_
    }
  }

  return $parse_error if $header; # i.e. we never saw today's section
  
  if ($before) {
    # We get here if today is the only section on the page.  Just append
    # the entry
    $newtext .= $entry
  }

  # Now post the updated entry
  if (not $wiki->PutWikiText($page . "/t", $newtext,
      "\@$display_name via Slack/Lightwood"))
  {
    return "Oh no!  An error occurred while trying to post your entry. " .
    ":disappointed:  Please report this to <\@U5T9JHE48>."
  }

  $page =~ s/ /_/g;
  return "OK!  I've added this to the <https://bao.chimenet.ca/wiki/index.php/$page|run notes>:\n```$entry```\n" .
  "Thanks for your diligence. :slightly_smiling_face:"
}

sub _post_allenby_note {
  my (%params) = @_;
  return _post_run_note_prefix("Allenby ", @_)
}

sub _post_run_note {
  my (%params) = @_;
  return _post_run_note_prefix("", @_)
}

# Post a thing to the wiki 
sub _post_run_note_prefix {
  local $_;
  my ($prefix, %params) = @_;

  my $wiki = Lightwood::Wiki->new();

  my @now = localtime time;

  # The text of what we're adding
  my $display_name = display_name($params{user}) || "<$params{user}>";
  my $entry = sprintf "* [%02i:%02i @%s] %s", @now[2,1], $display_name,
  $params{payload};

  #Remove trailing newline
  chomp $entry;

  #Syntactic sugar for multiple lines
  $entry =~ s/\n/\n::/g;

  print STDERR "ENTRY: $entry\n";

  my $day = sprintf "%04i-%02i-%02i", $now[5] + 1900, $now[4] + 1, $now[3];
  my @month_name = (qw(January February March April May June July August
    September October November December));
  my $page = $prefix . "Run Notes - " . $month_name[$now[4]] . " " . ($now[5] + 1900);

  print STDERR "ENTRY: $entry\n";

  # The message of a parsing error
  my $parse_error = "I'm sorry, I wasn't able to parse the run notes! " .
  ":slightly_frowning_face: If you report this to <\@U5T9JHE48>, include the " .
  "current time with the report.";

  # get the wikitext
  my $text = $wiki->GetWikiText($page);

  print STDERR "len(TEXT): ", length($text), "\n";

  # Run over lines in the text
  my @newtext = ();
  my $blanks = "";
  my $first = 1;
  my $header = 1;
  my $before = 1;
  for (split /^/, $text) {
    print STDERR "  LINE: $first $header $before :: $_";
    if ($first) {
      # Make sure things are kosher.  This should be the header
      if ($_ ne "{{Run Notes Header}}\n") {
        return $parse_error
      }
      push @newtext, $_;
      $first = 0;
    } elsif ($header) {
      # Here we're looking for today's section header
      if ($_ =~ /^== *\{\{Day|$day\}\} *==/) {
        $header = 0;
      }
      push @newtext, $_;
    } elsif ($before) {
      # Now looking for the end of the section
      if ($_ eq "\n") {
        # We collect blank lines here so we don't have to unspool them later
        $blanks .= $_;
        next
      } elsif ($_ =~ /^==[^=]/) {
        # We're at the end of this section.  Add the entry, then a blank,
        # then the current line (i.e. drop all the accumulated blanks)
        push @newtext, $entry . "\n\n" . $_;
        $before = 0;
        next
      }
      # Include all the deferred blank lines
      push @newtext, $blanks . $_;
      $blanks = "";
    } else {
      # We're done; just spool the rest of the text onto the output
      push @newtext, $_;
    }
  }

  return $parse_error if $header; # i.e. we never saw today's section
  
  if ($before) {
    # We get here if today is the only section on the page.  Just append
    # the entry
    push @newtext, "\n$entry";
  }

  # Now post the updated entry
  if (not $wiki->PutWikiText($page, join("", @newtext),
      "\@$display_name via Slack/Lightwood"))
  {
    return "Oh no!  An error occurred while trying to post your entry. " .
    ":disappointed:  Please report this to <\@U5T9JHE48>."
  }

  $page =~ s/ /_/g;
  return "OK!  I've added this to the <https://bao.chimenet.ca/wiki/index.php/$page|run notes>:\n```$entry```\n" .
  "Thanks for your diligence. :slightly_smiling_face:"
}

# Wait N microseconds and then say someting.  This tests dispatch timeout
# handling in Slack::SlashCommand.
sub _dev_wait_test {
  my (%params) = @_;

  my ($N, $text) = $params{payload} =~ /([0-9]+) (.*)/;

  return "Invalid time" unless $N;

  sleep $N;

  "`$text `";
}

# Dump the contents of the form data to slack.  This is a test
# of the "response" CODE handling
sub _dev_show_req {
  local $_;
  my (%params) = @_;

  my $response = "";
  for (sort keys %params) {
    $response .= "$_ = $params{$_}\n";
  }

  $response
}

# Create the app
sub new {
  my ($class) = @_;

  my $lightwood = Lightwood::Slack::App->new();

  # Add the "/lw" command
  my $lw = $lightwood->slash_command("lw",
    usage => "I'm Lightwood.  I can help you interact with the CHIMEwiki.  " .
    "To do so, use the `/lw` command.");

  # add /lw subcommands
  $lw->subcommand("post",
    help => "Add `message` (which may contain wiki markup) to the run notes " .
    "as a new entry.  The entry will be tagged with the current time and your " .
    "slack username",
    params => "message",
    dispatch => \&_post_run_note,
  );

  $lw->subcommand("allenby",
    help => "Add `message` (which may contain wiki markup) to the Allenby run notes " .
    "as a new entry.  The entry will be tagged with the current time and your " .
    "slack username",
    params => "message",
    dispatch => \&_post_allenby_note,
  );

  $lw->subcommand("tpost",
    help => "Test!",
    params => "message",
    dev => 1,
    dispatch => \&_tpost_run_note,
  );

  # A test of the string "response"
  $lw->subcommand("hello",
    help => "Greet Lightwood.",
    params => "",
    response => "Hi there.",
  );

  # A test of the functional "response"
  $lw->subcommand("showreq",
    help => "Show this command's payload",
    params => "",
    dev => 1,
    response => \&_dev_show_req,
  );
  
  # A test of the dispatch system
  $lw->subcommand("wait",
    help => "Wait _N_ seconds, then say _text_.",
    params => "N text",
    dev => 1,
    dispatch => \&_dev_wait_test,
  );

  $lightwood
}

1
