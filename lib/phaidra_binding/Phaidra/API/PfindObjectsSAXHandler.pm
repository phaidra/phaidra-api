#!/usr/bin/perl

use strict;
use warnings;

package Phaidra::API::PfindObjectsSAXHandler;

sub new
{
	my ($class, $fieldlist, $resultref) = @_;
	my $self = {};
	%{$self->{fieldlist}} = map { $_ => 1 } @$fieldlist;
	$self->{resultref} = $resultref;
	$self->{current_object} = {};
	$self->{in_field} = undef;
	$self->{hitTotal} = undef;
	bless($self, $class);
	return $self;
}

sub get_hitTotal
{
	my ($self) = @_;
	return $self->{hitTotal};
}

sub start_document
{
	my ($self) = @_;
}

sub start_element
{
	my ($self, $element) = @_;

	if($element->{Name} eq 'field')
	{
		if($self->{fieldlist}->{$element->{Attributes}->{name}})
		{
			$self->{in_field} = $element->{Attributes}->{name};
		}
	}
	elsif($element->{Name} eq 'object')
	{
		$self->{current_object} = {};
	}
	elsif($element->{Name} eq 'gfindObjects')
	{
		$self->{hitTotal} = $element->{Attributes}->{hitTotal};
	}
	elsif($element->{Name} eq 'permissions')
	{
		$self->{in_field} = 'permissions';
	}
}

sub characters
{
	my ($self, $element) = @_;

	if(defined($self->{in_field}))
	{
		$self->{current_object}->{$self->{in_field}} .= ' ' if(defined($self->{current_object}->{$self->{in_field}}));
		$self->{current_object}->{$self->{in_field}} .= $element->{Data};
	}
}

sub end_element
{
	my ($self, $element) = @_;

	if($element->{Name} eq 'field' || $element->{Name} eq 'permissions')
	{
		$self->{in_field} = undef;
	}
	elsif($element->{Name} eq 'object')
	{
		push @{$self->{resultref}}, $self->{current_object};
	}
}

1;
