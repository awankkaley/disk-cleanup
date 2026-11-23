#!/usr/bin/perl
# Test-only JSON inspector (JSON::PP ships with the system perl).
use strict;
use warnings;
use JSON::PP;

my $command = shift @ARGV // '';
my $text = do { local $/; <STDIN> };
my $doc = eval { JSON::PP->new->decode($text) };
if (!defined $doc || ref $doc ne 'HASH') { print "invalid JSON\n"; exit 1; }

my @problems;

sub show {
  my ($value) = @_;
  return 'null' unless defined $value;
  return $value ? 'true' : 'false' if JSON::PP::is_bool($value);
  return ref $value ? encode_json($value) : $value;
}

sub by_id {
  my ($list, $id) = @_;
  my ($found) = grep { $_->{id} eq $id } @{ $list // [] };
  return $found;
}

sub is_int { my ($v) = @_; defined $v && !ref $v && $v =~ /^\d+$/ }
sub is_int_or_null { my ($v) = @_; !defined $v || is_int($v) }
sub is_text { my ($v) = @_; defined $v && !ref $v && length $v }
sub one_of { my ($v, @allowed) = @_; defined $v && grep { $_ eq $v } @allowed }

sub expect_keys {
  my ($where, $hash, @keys) = @_;
  my $got = join ',', sort keys %$hash;
  my $want = join ',', sort @keys;
  push @problems, "$where keys: got [$got] want [$want]" if $got ne $want;
}

sub check {
  my ($ok, $message) = @_;
  push @problems, $message unless $ok;
}

sub schema_scan {
  expect_keys('scan', $doc, qw(schema_version command platform token
    token_expires_in_seconds disk recommended_total_bytes categories));
  check($doc->{schema_version} == 1, 'schema_version');
  check($doc->{command} eq 'scan', 'command');
  check($doc->{platform} eq 'macos', 'platform');
  check($doc->{token} =~ /^[0-9a-f]{8}$/, 'token');
  check($doc->{token_expires_in_seconds} == 900, 'ttl');
  expect_keys('disk', $doc->{disk}, qw(total_bytes free_bytes));
  check(is_int($doc->{disk}{$_}), "disk.$_") for qw(total_bytes free_bytes);
  check(is_int($doc->{recommended_total_bytes}), 'recommended_total_bytes');
  schema_category($_) for @{ $doc->{categories} };
}

sub schema_category {
  my ($cat) = @_;
  my $id = $cat->{id} // '?';
  my @keys = qw(id label group size_bytes item_count status recommended risk
    impact requires_flag);
  push @keys, 'buckets' if $id eq 'node-modules-stale';
  expect_keys("category $id", $cat, @keys);
  check(is_text($cat->{$_}), "$id.$_") for qw(id label impact);
  check(one_of($cat->{group}, qw(system browser developer projects)), "$id.group");
  check(one_of($cat->{status}, qw(ok empty not_found skipped_running
    skipped_needs_admin skipped_no_permission unavailable)), "$id.status");
  check(one_of($cat->{risk}, qw(safe rebuild_needed irreversible)), "$id.risk");
  check(JSON::PP::is_bool($cat->{recommended}), "$id.recommended type");
  check((!!$cat->{recommended}) == ($cat->{risk} eq 'safe'), "$id.recommended value");
  check(is_int_or_null($cat->{$_}), "$id.$_") for qw(size_bytes item_count);
  my $flag = $id eq 'trash' ? '--empty-trash' : undef;
  check((show($cat->{requires_flag}) eq show($flag)), "$id.requires_flag");
  return unless $id eq 'node-modules-stale';
  for my $bucket (@{ $cat->{buckets} }) {
    expect_keys('bucket', $bucket, qw(id min_idle_days project_count size_bytes));
    check(is_int($bucket->{$_}), "bucket.$_") for qw(min_idle_days project_count size_bytes);
  }
  check(join(',', map { $_->{id} } @{ $cat->{buckets} }) eq '30-90,90-180,180+', 'bucket ids');
}

sub schema_clean {
  expect_keys('clean', $doc, qw(schema_version command platform disk_before
    disk_after freed_total_bytes results log_file_written log_location_hint));
  check($doc->{schema_version} == 1, 'schema_version');
  check($doc->{command} eq 'clean', 'command');
  check($doc->{platform} eq 'macos', 'platform');
  for my $key (qw(disk_before disk_after)) {
    expect_keys($key, $doc->{$key}, 'free_bytes');
    check(is_int($doc->{$key}{free_bytes}), "$key.free_bytes");
  }
  check(is_int($doc->{freed_total_bytes}), 'freed_total_bytes');
  check(JSON::PP::is_bool($doc->{log_file_written}), 'log_file_written');
  my $total = 0;
  for my $result (@{ $doc->{results} }) {
    my $id = $result->{id} // '?';
    expect_keys("result $id", $result, qw(id label freed_bytes status error_code));
    check(is_text($result->{$_}), "$id.$_") for qw(id label);
    check(is_int($result->{freed_bytes}), "$id.freed_bytes");
    check(one_of($result->{status}, qw(cleaned partial skipped_running
      skipped_no_permission not_found unavailable failed)), "$id.status");
    my %codes = (
      cleaned => ['null'], partial => ['SOME_ITEMS_REMAIN'],
      skipped_running => ['APP_RUNNING'], skipped_no_permission => ['PERMISSION_DENIED'],
      not_found => ['NOT_FOUND'], unavailable => [qw(TOOL_UNAVAILABLE CUSTOM_LOCATION)],
      failed => [qw(TOOL_FAILED GUARD_REFUSED INTERNAL)],
    );
    check(one_of(show($result->{error_code}), @{ $codes{ $result->{status} } // [] }),
      "$id.error_code does not belong to its status");
    $total += $result->{freed_bytes} if is_int($result->{freed_bytes});
  }
  check($total == $doc->{freed_total_bytes}, 'freed_total_bytes is the sum');
}

sub schema_error {
  expect_keys('error doc', $doc, qw(schema_version error));
  check($doc->{schema_version} == 1, 'schema_version');
  expect_keys('error', $doc->{error}, qw(code message));
  check(one_of($doc->{error}{code}, qw(USAGE UNKNOWN_CATEGORY TOKEN_MISSING
    TOKEN_INVALID TOKEN_EXPIRED CATEGORY_NOT_IN_SCAN TRASH_FLAG_REQUIRED
    DEEP_SCAN_REQUIRED INVALID_ARGUMENT UNSUPPORTED_PLATFORM INTERNAL)), 'error code');
  check(is_text($doc->{error}{message}), 'error message');
}

sub walk_strings {
  my ($node, $key) = @_;
  if (ref $node eq 'HASH') { walk_strings($node->{$_}, $_) for keys %$node; return; }
  if (ref $node eq 'ARRAY') { walk_strings($_, $key) for @$node; return; }
  return if !defined $node || ref $node;
  return if $key eq 'log_location_hint'
    && $node eq '~/Library/Application Support/disk-cleanup/logs';
  push @problems, "$key contains a path separator" if $node =~ m{[/\\]};
}

if ($command eq 'get') {
  my $node = $doc;
  $node = ref $node eq 'ARRAY' ? $node->[$_] : $node->{$_} for split /\./, $ARGV[0];
  print show($node), "\n";
} elsif ($command eq 'cat') {
  print show(by_id($doc->{categories}, $ARGV[0])->{ $ARGV[1] }), "\n";
} elsif ($command eq 'res') {
  print show(by_id($doc->{results}, $ARGV[0])->{ $ARGV[1] }), "\n";
} elsif ($command eq 'bucket') {
  my $cat = by_id($doc->{categories}, 'node-modules-stale');
  print show(by_id($cat->{buckets}, $ARGV[0])->{ $ARGV[1] }), "\n";
} elsif ($command eq 'ids') {
  print join(',', map { $_->{id} } @{ $doc->{categories} // $doc->{results} }), "\n";
} elsif ($command eq 'recommended-sum') {
  my $sum = 0;
  $sum += $_->{size_bytes} // 0
    for grep { $_->{status} eq 'ok' && $_->{recommended} } @{ $doc->{categories} };
  print "$sum\n";
} elsif ($command eq 'ok-ids') {
  print join(',', map { $_->{id} } grep { $_->{status} eq 'ok' } @{ $doc->{categories} }), "\n";
} elsif ($command eq 'schema') {
  my %checks = (scan => \&schema_scan, clean => \&schema_clean, error => \&schema_error);
  $checks{ $ARGV[0] }->();
} elsif ($command eq 'strings-clean') {
  walk_strings($doc, '');
} else {
  push @problems, "unknown command $command";
}

if (@problems) { print join('; ', @problems), "\n"; exit 1; }
exit 0;
