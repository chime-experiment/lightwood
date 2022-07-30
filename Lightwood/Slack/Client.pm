package Lightwood::Slack::Client;

use Exporter;
our @ISA = qw(Exporter);

our %EXPORT_TAGS = (
  meta => [qw(slack_api_config)],
  info => [qw(display_name)],
  formatting => [qw(mrkdwn_sect div_sect plain_sect)],
  posting => [qw(ack send_to_webhook post_message post_ephemeral)],
);
our @EXPORT_OK =(
  @{$EXPORT_TAGS{meta}},
  @{$EXPORT_TAGS{info}},
  @{$EXPORT_TAGS{formatting}},
  @{$EXPORT_TAGS{posting}}
  );

use JSON;
use LWP::UserAgent;
use WWW::Form::UrlEncoded qw/build_urlencoded/;

# Set up the UA.
my $ua = LWP::UserAgent->new;
$ua->agent("Lightwood/1.0");
$ua->cookie_jar({});
push @{ $ua->requests_redirectable }, 'POST';

# Configure the API
my $SLACK_API_URL;
my $SLACK_TOKEN;
sub slack_api_config {
  my ($url, $token) = @_;
  die "Bad Slack API URL" unless ($url);
  die "Bad Slack API token" unless ($token);

  $url .= "/" unless ($url =~ '/$');

  $SLACK_TOKEN = $token;
  $SLACK_API_URL = $url;
}

# Takes a typical response from Lightwood callbacks and formats it as
# a JSON string.
#
# This can be:
# - a false value; returns undef
# - an array-ref, treated as an array of hashes which is JSON converted
#   and then encapsulated in a "blocks" section of a JSON object
# - a string starting with "JSON:".  The "JSON:" is stripped and the
#   rest is assumed to be already formatted JSON
# - anything else, which is treated as a mrkdwn message
sub format_message {
  my $message = shift;

  return undef unless $message;

  if (ref($message) eq "ARRAY") {
    return encode_json { blocks => $message };
  } elsif ($message =~ /^JSON:(.*)$/) {
    return $1;
  } 

  # Otherwise, be naive and assume this is a mrkdwn-formatted string
  format_message([ mrkdwn_sect($message) ])
}

# Send a request to the web api.  Returns a decoded JSON object as a hash
sub web_api {
  my ($target, $use_json, %params) = @_;

  die "Slack API access before configuration!" if (not defined $SLACK_API_URL);

  my $req = HTTP::Request->new(POST => $SLACK_API_URL . $target);

  if ($use_json) {
    my $data = encode_json(\%params);

    $req->content_type('application/json; charset=utf-8');
    $req->header(Authorization => "Bearer $SLACK_TOKEN");
    $req->content($data);
  } else {
    $params{token} = $SLACK_TOKEN;

    my $data = build_urlencoded(%params);

    $req->content_type('application/x-www-form-urlencoded; charset=utf-8');
    $req->content($data);
  }

  print STDERR "REQ:\n", $req->as_string, "\n";

  my $res = $ua->request($req);

  print STDERR "RES:\n", $res->as_string, "\n";

  unless ($res->is_success) {
    print STDERR "REQ:\n", $req->as_string, "\n";
    print STDERR "RES:\n", $res->as_string, "\n";
    return undef
  }

  my $json = decode_json($res->content());
  return $json
}

# Given a user ID, return a display name
sub display_name {
  my $user = shift;

  my $user_info = web_api("users.info", 0, user => $user);

  # Error handling
  return undef unless $user_info;
  return undef unless $$user_info{ok};

  my $disp = $$user_info{user}{profile}{display_name};

  #Fallback
  $disp ||= $$user_info{user}{name};

  print STDERR "DISP: $disp\n";
  
  $disp
}

# Send a $message to $channel via $method (which is probably chat.postMessage
# or chat.postEphemeral; see functions below)
sub post_via {
  local $_;
  my ($method, $message, %data) = @_;

  print STDERR "post_via: $method $message\n";
  for (sort keys %data) {
    print STDERR "  $_ = $data{$_}\n";
  }

  my %args = (
    channel => $data{channel},
  );

  # To reduce chatter, we always post as a reply, if possible
  if ($data{thread_ts}) {
    $args{thread_ts} = $data{thread_ts};
  } elsif ($data{ts}) {
    $args{thread_ts} = $data{ts};
  }

  $args{attachments} = $data{attachments} if ($data{attachments});

  if (ref($message) eq "ARRAY") {
    $args{blocks} = $message;

    # Add a "text" if provided
    $args{text} = $data{text} if ($data{text});
  } else {
    $args{text} = $message;
  }

  my $ret = web_api($method, 1, %args);

  print STDERR "post_via <- $ret\n";

  return $ret
}

sub post_message {
  # Simple
  return post_via("chat.postMessage", @_);
}

sub post_ephemeral {
  my ($message, %data) = @_;

  # Scrub ts values: ephemeral messages to a thread aren't shown if there isn't
  # already a thread, so this just simplifies things
  delete $data{thread_ts};
  delete $data{ts};

  return post_via("chat.postEphemeral", $message, %data);
}

# Send the specified message to the provided webhook URL
sub send_to_webhook {
  my ($url, $message) = @_;

  # Format the message
  $message = format_message($message || "INTERNAL ERROR: MESSAGE MISSING!");

  # POST it
  my $req = HTTP::Request->new(POST => $url);
  $req->content_type('application/json');
  $req->content($message);

  my $res = $ua->request($req);

  print STDERR "ERROR from $url!" unless $res->is_success;

  0
}

# Acknowledge the receipt of a command.  This must happen within 3 seconds
# of the request, so no latency here.  An empty ack can be sent to give
# Lightwood time to respond later.
sub ack {
  my ($message) = @_;

  # Format message
  $message = format_message($message);

  print STDERR "ACK: " . ($message || "(nil)") . "\n";

  print "HTTP/1.0 200 OK\r\n";
  if ($message) {
    print "Content-Type: application/json;charset=UTF-8\r\n";
    print "Content-Length: " . length($message) . "\r\n";
  } else {
    print "Content-Length: 0\r\n";
  }
  print "\r\n";
  print $message if $message;

  0
}

# Block/message formatting helpers
sub div_sect { { type => "divider" } }
sub mrkdwn_sect {
  { type => "section", text => { type => "mrkdwn", text => shift }}
}
sub plain_sect {
  { type => "section", text => { type => "plain_text", text => shift }}
}

1
