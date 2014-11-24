#!/usr/bin/env perl
package LoanRec;
use strict;
use Carp;

use Data::Dumper;

__PACKAGE__->run(@ARGV) unless caller();

sub run{
	croak "Must provide two file names" unless @ARGV == 2;
	open my $fh1, "<", $ARGV[0] or die "Failed to open file: $!";
	my @trades1 = parseTrades($fh1);
	open my $fh2, "<", $ARGV[1] or die "Failed to open file: $!";
	my @trades2 = parseTrades($fh2);

	my ($missingTrades, $quantityBreaks, $missingReturns) = reconcile(\@trades1, \@trades2);
	print "Missing trade: $_\n" foreach (@$missingTrades);
	print "Quantity break: $_\n" foreach (@$quantityBreaks);
	print "Missing return: $_\n" foreach (@$missingReturns);
}

sub reconcile{
	my ($trades1, $trades2) = @_;
	
	my (%securities, %trades1BySecurity, %trades2BySecurity);
	foreach (@$trades1) {
		$securities{$_->{security}}++;
		$trades1BySecurity{$_->{security}} = $_;
	}
	foreach (@$trades2) {
		$securities{$_->{security}}+=2;
		$trades2BySecurity{$_->{security}} = $_;
	}

	my (@missing, @breaks, @missingReturns);	# Collect missing trades and vreaks in their own arrays
	while (my ($security, $count) = each %securities) {
		if ($count != 3) {
			#only in one of the lists
			my $extraTrade = ($count == 1) ? $trades1BySecurity{$security} :
										$trades2BySecurity{$security};
			push(@missing, "Client $extraTrade->{client} has an extra trade for $extraTrade->{quantity} of $extraTrade->{security}");
		}
		else {
			# This appears in both sets
			my $set1Trade = $trades1BySecurity{$security};
			my $set2Trade = $trades2BySecurity{$security};

			# Quantity on trade
			if ($set1Trade->{quantity} != $set2Trade->{quantity}) {
				my (@orderedTrades) = sort({$a->{quantity} <=> $b->{quantity}} ($set1Trade, $set2Trade));
				push(@breaks, "Quantity mismatch, client $orderedTrades[0]->{client} has quantity".
					" $orderedTrades[0]->{quantity} of $security on trade $orderedTrades[0]->{clientRef},".
					" should be $orderedTrades[1]->{quantity} ");
			}
			if (exists $set1Trade->{return} && exists $set2Trade->{return}) {
				#do they match
				my ($return1, $return2) = ($set1Trade->{return}, $set2Trade->{return});
				if ($return1->{quantity} != $return2->{quantity}) {
					my (@orderedTrades) = sort({$a->{quantity} <=> $b->{quantity}} ($return1, $return2));
					push(@breaks, "Quantity mismatch, client $orderedTrades[0]->{client} has quantity".
						" $orderedTrades[0]->{quantity} of $security on return $orderedTrades[0]->{clientRef},".
						" should be $orderedTrades[1]->{quantity} ");
				}
			}
			if ((exists $set1Trade->{return}) != (exists $set2Trade->{return})) {
				my ($missingReturn, $return);
				if (exists $set1Trade->{return}) {
					($missingReturn, $return) = ($set2Trade, $set1Trade->{return});
				}
				else {
					($missingReturn, $return) = ($set1Trade, $set2Trade->{return});
				}
				push(@missingReturns, "Client $missingReturn->{client} is missing a return for $return->{quantity} of $return->{security} on trade $missingReturn->{clientRef}"); 
			}
		}
	}
	return (\@missing, \@breaks, \@missingReturns);
}

sub parseTrades{
	my $fh = shift;
	my %trades;			#To merge trades and returns collect the trades and returns
	my %returns;		#by their client refs
	while (<$fh>) {
		my %fields;
		@fields{qw(client tradeReturn clientRef security quantity parent)} = split('\s+');
		# Might have a header, if the tradeReturn value is invalid then skip it
		next unless $fields{tradeReturn} =~ m{^(:?T|R)$};

		delete $fields{parent} unless defined $fields{parent};	# Drop undefined parent field if it didn't exist

		if ($fields{tradeReturn} eq 'T') {
			$trades{$fields{clientRef}} = \%fields;
		}
		elsif ($fields{tradeReturn} eq 'R') {
			if (defined $fields{parent}) {
				$returns{$fields{parent}} = \%fields;
			}
			else {
				carp('No parent ref on return transaction');
			}
		}
	}

	foreach my $parent (keys %returns) {
		if (exists $trades{$parent}) {
			$trades{$parent}->{return} = $returns{$parent};
		}
		else {
			carp("Return with parent ref '$parent' not found");
		}
	}
	return values %trades;
}
sub smallerTrade{
	my ($trade1, $trade2) = @_;
	return ($trade1->{quantity} < $trade2->{quantity}) ? $trade1 : $trade2;
}
1;
