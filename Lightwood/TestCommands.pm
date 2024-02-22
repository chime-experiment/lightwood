package Lightwood::TestCommands;

# These are the default commands.  They mostly do nothing
# other than test Lightwood itself.

use strict;

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

# This is the actual command list that Lightwood proper makes use of.
our %commands = (
  hello => {
    help => "Greet Lightwood.",
    params => "",
    response => "Hi there.",
  },

  "showreq" => {
    help => "Show this command's payload",
    params => "",
    dev => 1,
    response => \&_dev_show_req,
  },

  "wait" => {
    help => "Wait _N_ seconds, then say _text_.",
    params => "N text",
    dev => 1,
    dispatch => \&_dev_wait_test,
  },
);

1
