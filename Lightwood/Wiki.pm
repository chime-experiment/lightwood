package Lightwood::Wiki;

use strict;
use utf8;

use JSON;
use Encode;
use LWP::UserAgent;

# API Config
my $WIKIAPI;
my $WIKIUSER;
my $WIKIPASS;
sub wiki_api_config {
  my ($url, $user, $pass) = @_;
  print STDERR "Wiki config $url $user $pass\n" ;
  die "Bad Wiki API URL" unless ($url);
  die "Bad Wiki API user" unless ($user);
  die "Bad Wiki API password" unless ($pass);

  $WIKIAPI = $url;
  $WIKIUSER = $user;
  $WIKIPASS = $pass;
}

# POST a request to the Wiki.  Returns the response object.
# Pass in a hash of parameter name/values.
sub Wikireq {
  local $_;
  my ($self, %params) = @_;

  print STDERR "Wikireq($WIKIAPI, ", join(", ", %params), ")\n";

  # Add default format
  $params{format} ||= "json";

  # Explicit UTF-8 encode -- HTTP::Message will encode to latin1 if
  # passed decoded data
  my $utf8_params = {};
  for (keys %params) {
    $$utf8_params{$_} = encode_utf8($params{$_})
  }

  $$self{ua}->post($WIKIAPI,
    'Content-type' => 'application/x-www-form-urlencoded; charset=utf-8',
    Content => $utf8_params
  );
}

# Get an edit token
sub GetWikiToken {
  my ($self, $page) = @_;

  my $res = $self->Wikireq(action => "query", prop => "info", titles => $page,
    intoken => "edit");
  
  (my $tok) = $res->content() =~ /"edittoken":"([^"]*)"/;

  $tok =~ s/\\\\/\\/g; # JSON "decode"

  $tok;
}

# Replace the contents of $page with $text, with edit summary $summary
sub PutWikiText {
  my ($self, $page, $text, $summary) = @_;

  print STDERR "PutWikiText(\"$page\", \"[...]\"{" . length($text) . "}, \"$summary\")\n";

  # Get the edit token
  my $editToken = $self->GetWikiToken($page);

  my $res = $self->Wikireq(action => "edit", token => $editToken, title => $page,
    text => $text, summary => $summary, bot => 1, notminor => 1);

  return $res->is_success;
}

# Get the text of a page
sub GetWikiText {
  my ($self, $page) = @_;

  my $res = $self->Wikireq(format => "xml", action => "query",
      prop => "revisions", titles => $page, rvprop => "content");

  if ($res->content !~ /<rev/) {
    # Page misisng
    print STDERR "Wiki page has no text: " . $res->content . "\n";
    return undef;
  }

  my ($text) = $res->content =~ /<rev [^>]*>(.*)<\/rev>/s;

  $text ||= ""; # Cast away some errors

  # Decode
  $text = decode_utf8($text);
  $text =~ s/&amp;/&/g;
  $text =~ s/&quot;/"/g;
  $text =~ s/&lt;/</g;
  $text =~ s/&gt;/>/g;

  $text;
}

sub new {
  my $class = shift;

  my $ua;
  my $res;

  # Set up the UA.
  $ua = LWP::UserAgent->new;
  $ua->agent("Lightwood/1.0");
  $ua->cookie_jar({});
  push @{ $ua->requests_redirectable }, 'POST';

  my $this = bless {
    ua => $ua,
  }, $class;

  #get the login token from the Wiki
  $res = $this->Wikireq(action => "query", meta => "tokens", type => "login");
  die $res->content() unless ($res->is_success);

  # get the token
  my ($toke) = $res->content() =~ /\"logintoken\":\"([^"]*)\"/;
  die $res->content() unless $toke;

  $toke =~ s/\\\\/\\/g;

  die "Wiki request before config" unless defined $WIKIAPI;

  #login to the wiki
  $res = $this->Wikireq(action => "login", lgname => $WIKIUSER,
      lgpassword => $WIKIPASS, lgtoken => $toke);
  return undef unless ($res->is_success);

  return $this
}

1
