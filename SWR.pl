﻿#!/usr/bin/perl
use strict;
use Tkx;
use DBI;
use POSIX qw(ceil);
use Cwd qw(cwd);
use File::Basename;
use Spreadsheet::WriteExcel;
Tkx::package_require('widget::statusbar');
Tkx::package_require('widget::dialog');
Tkx::package_require('img::png');
Tkx::package_require('img::ico');
Tkx::lappend('::auto_path', 'lib');
Tkx::package_require('tkdnd');

#remove Tkx error warning window
Tkx::set("perl_bgerror", sub{
	splice(@_, 0, 3);
});
Tkx::eval(<<'EOT');
proc bgerror {msg} {
	global perl_bgerror
	$perl_bgerror $msg
}
EOT

my %paras; #global parameters
my %wdg; #global widget

#initial parameters
$paras{last_in_dir} = $paras{last_out_dir} = cwd;
$paras{db} = 'Import a database file generated by MSDB';
$paras{motif_info} = 'Input motifs, use space to separate';
$paras{origin} = $paras{complex} = $paras{type} = ['unlimited'];
$paras{csrow} = $paras{cerow} = $paras{trows} = 0; # current start row and total rows
$paras{eprows} = 100; # number of rows of each page
$wdg{'os'}=Tkx::tk_windowingsystem();

my $mw = Tkx::widget->new('.');
$mw->g_wm_geometry("710x650");
$mw->g_wm_title("Search Within Results");
$mw->g_wm_protocol('WM_DELETE_WINDOW', sub{on_exit()});

if($wdg{'os'} eq "win32"){
	Tkx::wm_iconbitmap($mw, -default => "MSDB.ico");
} elsif($wdg{'os'} eq "x11"){
	Tkx::wm_iconphoto($mw, "-default", Tkx::image_create_photo(-file => 'MSDB.ico'));
}

$mw->g_grid_rowconfigure(0, -weight => 1);
$mw->g_grid_columnconfigure(0, -weight => 1);

my $frame = $mw->new_ttk__frame(-padding => 10);
$frame->g_grid(-sticky => "wnes");
$frame->g_grid_columnconfigure(0, -weight => 1);

#drag file
Tkx::tkdnd__drop___target_register($frame,'*');
Tkx::bind($frame, '<<Drop:DND_Files>>', [sub{import_database(shift)}, Tkx::Ev('%D')]);


my $import = $frame->new_ttk__frame;
$import->g_grid(-sticky => 'we');
$import->new_ttk__button(
	-text => "Import Database File",
	-command => sub{import_database()},
)->g_grid(
	-column => 0,
	-row => 0,
	-sticky => "w",
);
$import->new_ttk__entry(
	-textvariable => \$paras{db},
	-state => 'readonly',
)->g_grid(
	-padx => "5 0",
	-column => 1,
	-row => 0,
	-sticky => 'we',
);
$import->g_grid_columnconfigure(1, -weight => 1);

my $tabs = $frame->new_ttk__notebook();
$tabs->g_grid(
	-sticky => "we",
	-pady => 10,
);
$tabs->g_bind("<<NotebookTabChanged>>", sub{change_tab_bn()});
my $tab1 = $tabs->new_ttk__frame(-padding => 5);
my $tab2 = $tabs->new_ttk__frame(-padding => 5);
$tabs->add($tab1, -text => "Filter Criteria");
$tabs->add($tab2, -text => "Execute SQL");
$tab1->g_grid_columnconfigure(0, -weight => 1);

#Filter Criteria
my $lfot = $tab1->new_ttk__frame;
$lfot->g_grid(
	-column => 0,
	-row => 0,
	-sticky => "we",
);
my $mf = $lfot->new_ttk__frame;
$mf->g_grid(
	-sticky => "we",
	-pady => 5,
);
my $filter_motif = $mf->new_ttk__combobox(
	-values => ['Motif Type', 'Motif Length'],
	-textvariable => \$paras{motif_tl},
	-state => 'readonly',
	-width => 18,
);
$filter_motif->g_grid(
	-column => 0,
	-row => 0,
	-sticky => "w",
);
$filter_motif->current(0);
$filter_motif->g_bind("<<ComboboxSelected>>", sub{motif_type_or_len()});
$wdg{motif_type} = $mf->new_ttk__combobox(
	-textvariable => \$paras{motif},
	-values => ["unlimited"],
	-width => 17,
);
$wdg{motif_type}->current(0);
$wdg{motif_type}->g_grid(
	-column => 1,
	-row => 0,
	-sticky => "w",
	-padx => 5,
);
$mf->new_ttk__label(
	-textvariable => \$paras{motif_info},
)->g_grid(
	-column => 2,
	-row => 0,
	-sticky => "w",
);

my $rf = $lfot->new_ttk__frame;
$rf->g_grid(
	-sticky => "we",
	-pady => "0 5",
);
my $rol = $rf->new_ttk__combobox(
	-values => ["Number of Repeats","Length of SSR"],
	-textvariable => \$paras{rep_or_len},
	-width => 18,
	-state => 'readonly',
);
$rol->g_grid(
	-column => 0,
	-row => 0,
	-sticky => "w",
	-padx => '0 5',
);
$rol->current(0);
my $filter_rep = $rf->new_ttk__combobox(
	-textvariable => \$paras{rep_f},
	-values => ['Equals', 'Dose Not Equal', 'Less Than', 'Greater Than', 'Between'],
	-width => 17,
	-state => 'readonly',
);
$filter_rep->g_grid(
	-column => 1,
	-row => 0,
	-sticky => "w",
);
$filter_rep->current(0);
$filter_rep->g_bind("<<ComboboxSelected>>", sub{change_repeats_filter()});
$wdg{min_label} = $rf->new_ttk__label(-text => "Min:");
$wdg{min_entry} = $rf->new_ttk__combobox(
	-textvariable => \$paras{rep_min},
	-values => ['unlimited'],
	-width => 12,
);
$wdg{min_entry}->current(0);
$wdg{min_entry}->g_grid(
	-column => 2,
	-row => 0,
	-sticky => "w",
	-padx => 5,
);
$wdg{max_label} = $rf->new_ttk__label(-text => "Max:");
$wdg{max_entry} = $rf->new_ttk__combobox(
	-textvariable => \$paras{rep_max},
	-values => ['unlimited'],
	-width => 12,
);
$wdg{max_entry}->current(0);

my $tf = $lfot->new_ttk__frame;
$tf->g_grid(
	-sticky => "we",
	-pady => "0 5",
);
$tf->new_ttk__label(
	-text => "SSR Type:",
)->g_grid(
	-column => 0,
	-row => 0,
	-sticky => "w",
);
$wdg{type} = $tf->new_ttk__combobox(
	-textvariable => \$paras{ssr_type},
	-values => $paras{type},
	-width => 10,
	-state => 'readonly',
);
$wdg{type}->g_grid(
	-column => 1,
	-row => 0,
	-sticky => "w",
);
$wdg{type}->current(0);
$tf->new_ttk__label(
	-text => "SSR Complexity:",
)->g_grid(
	-column => 2,
	-row => 0,
	-sticky => "w",
	-padx => "5 0",
);
$wdg{complex} = $tf->new_ttk__combobox(
	-textvariable => \$paras{ssr_complex},
	-values => $paras{complex},
	-width => 10,
	-state => 'readonly',
);
$wdg{complex}->g_grid(
	-column => 3,
	-row => 0,
	-sticky => 'w',
);
$wdg{complex}->current(0);
$tf->new_ttk__label(
	-text => "SSR Source:",
)->g_grid(
	-column => 4,
	-row =>0,
	-sticky => "w",
	-padx => "5 0",
);
$wdg{origin} = $tf->new_ttk__combobox(
	-textvariable => \$paras{ssr_origin},
	-values => $paras{origin},
	-width => 18,
	-state => 'readonly',
);
$wdg{origin}->g_grid(
	-column => 5,
	-row => 0,
	-sticky => "w",
);
$wdg{origin}->current(0);

$tab1->new_ttk__button(
	-text => "Execute",
	-command => sub{query_by_filter()},
	-image => Tkx::image_create_photo(-file => 'images/exec.png'),
	-compound => 'top',
)->g_grid(
	-sticky => "wnes",
	-column => 1,
	-row => 0,
);

$tab2->new_ttk__label(
	-text => "SQL String:",
)->g_grid(
	-sticky => "w",
	-columnspan => 2,
);
$wdg{sql} = $tab2->new_tk__text(
	-height => 5,
	-borderwidth => 2,
	-relief => "groove",
);
$wdg{sql}->g_grid(
	-sticky => "wnes", 
	-column => 0, 
	-row => 1
);
$tab2->g_grid_columnconfigure(0, -weight => 1);
$tab2->new_ttk__button(
	-text => "Execute Query",
	-image => Tkx::image_create_photo(-file => 'images/exec.png'),
	-compound => 'top',
	-command => sub{query_by_sql()},
)->g_grid(
	-sticky => "wnes",
	-column => 1, 
	-row => 1,
);

$frame->new_ttk__label(
	-text => "Error message from database engine:",
)->g_grid(-sticky => "w");
$frame->new_ttk__entry(
	-textvariable => \$paras{error},
	-state => "readonly",
)->g_grid(-sticky => "we");
$frame->new_ttk__label(
	-text => "Data returned:",
)->g_grid(-sticky => "w");

my $treef = $frame->new_ttk__frame;
$treef->g_grid(-sticky => "wnes");
$frame->g_grid_rowconfigure(5, -weight => 1);
$treef->g_grid_rowconfigure(0, -weight => 1);
$wdg{tree} = $treef->new_ttk__treeview(-show => 'headings',);
$wdg{tree}->g_grid(
	-sticky => "wnes",
	-column => 0,
	-row => 0,
);
$treef->g_grid_columnconfigure(0, -weight => 1);
my $scrolly = $treef->new_ttk__scrollbar(
	-orient => 'vertical',
	-command => [$wdg{tree}, 'yview'],
);
$scrolly->g_grid(
	-column => 1,
	-row => 0,
	-sticky => "ns",
);
$wdg{tree}->configure(-yscrollcommand => [$scrolly, 'set']);
my $scrollx = $treef->new_ttk__scrollbar(
	-orient => 'horizontal',
	-command => [$wdg{tree}, 'xview'],
);
$scrollx->g_grid(
	-column => 0,
	-row => 1,
	-sticky => "we",
);
$wdg{tree}->configure(-xscrollcommand => [$scrollx, 'set']);

my $ff = $frame->new_ttk__frame;
$ff->g_grid(
	-sticky => "we",
	-pady => "5 0",
);
$ff->new_ttk__button(
	-text => "<",
	-command => sub{pre_page()},
)->g_grid(
	-column => 0,
	-row => 0,
	-sticky => "w",
);
$ff->new_ttk__label(
	-textvariable => \$paras{csrow},
)->g_grid(
	-column => 1,
	-row => 0,
	-sticky => "w",
);
$ff->new_ttk__label(
	-text => " - ",
)->g_grid(
	-column => 2,
	-row => 0,
	-sticky => "w",
);
$ff->new_ttk__label(
	-textvariable => \$paras{cerow},
)->g_grid(
	-column => 3,
	-row => 0,
	-sticky => "w",
);
$ff->new_ttk__label(
	-text => " of ",
)->g_grid(
	-column => 4,
	-row => 0,
	-sticky => "w",
);
$ff->new_ttk__label(
	-textvariable => \$paras{trows},
)->g_grid(
	-column => 5,
	-row => 0,
	-sticky => "w",
);
$ff->new_ttk__button(
	-text => ">",
	-command => sub{next_page()},
)->g_grid(
	-column => 6,
	-row => 0,
	-sticky => "w",
);
$ff->new_ttk__frame()->g_grid(
	-column => 7,
	-row => 0,
	-sticky => "we",
);
$ff->g_grid_columnconfigure(7, -weight => 1);
$ff->new_ttk__button(
	-text => "Export for Primer3",
	-command => sub{export_for_primer()},
)->g_grid(
	-column => 8,
	-row => 0,
	-sticky => 'e',
);
$ff->new_ttk__button(
	-text => "Export SSRs",
	-command => sub{export_format_ssrs()},
)->g_grid(
	-column => 9,
	-row => 0,
	-sticky => "e",
);
$wdg{export_bn} = $ff->new_ttk__button(
	-text => "Export Data",
	-command => sub{export_data()},
	-state => "disabled",
);
$wdg{export_bn}->g_grid(
	-column => 10,
	-row => 0,
	-sticky => "e",
);

my $status = $mw->new_widget__statusbar();
$status->g_grid(-sticky => "we");
$status->add(
	$status->new_ttk__label(
		-textvariable => \$paras{msg}, 
		-anchor => "w", 
	)
);

Tkx::MainLoop;



# gui functions
sub motif_type_or_len{
	if($paras{motif_tl} eq 'Motif Type'){
		$wdg{motif_type}->configure(-values => ['unlimited'], -state => "normal");
		$paras{motif_info} = 'Input motifs, use space to separate';
	}else{
		$wdg{motif_type}->configure(-values => ['unlimited',1,2,3,4,5,6], -state => "readonly");
		$paras{motif_info} = 'Select length of motif';
	}
	$wdg{motif_type}->current(0);
}
sub change_repeats_filter{
	if($paras{rep_f} eq 'Between'){
		$wdg{min_entry}->g_grid_forget();
		$wdg{min_label}->g_grid(-column => 2, -row => 0, -padx => "5 0");
		$wdg{min_entry}->g_grid(-column => 3, -row => 0);
		$wdg{max_label}->g_grid(-column => 4, -row => 0, -padx => "5 0");
		$wdg{max_entry}->g_grid(-column => 5, -row => 0);
	}else{
		$wdg{min_label}->g_grid_forget();
		$wdg{min_entry}->g_grid_forget();
		$wdg{max_label}->g_grid_forget();
		$wdg{max_entry}->g_grid_forget();
		$wdg{min_entry}->g_grid(-column => 2, -row => 0, -padx => "5 0");
	}
}
sub create_tree_headings{
	my $sth = shift;
	my $heads = $sth->{NAME};
	$wdg{tree}->configure(-columns => $heads);
	my $width = ceil($wdg{tree}->g_winfo_width / @$heads);
	foreach (@$heads){
		$wdg{tree}->heading($_, -text => $_);
		$wdg{tree}->column($_, -width => $width, -stretch => 1);
	}
}
sub insert_to_tree{
	my $sth = shift;
	if($paras{ids}){
		$wdg{tree}->delete(join " ", @{$paras{ids}});
		$paras{ids} = [];
	}
	while( my $rv = $sth->fetchrow_arrayref){
		my $id = $wdg{tree}->insert("", "end", -values => $rv);
		push @{$paras{ids}}, $id;
	}
	
}
sub config_paras{
	my $sql = "SELECT filename FROM file";
	$paras{origin} = $paras{dbh}->selectcol_arrayref($sql);
	unshift @{$paras{origin}}, 'unlimited';
	$wdg{origin}->configure(-values => $paras{origin});
	
	foreach ( qw(p ip cd icd cx icx) ){
		$sql = "SELECT * FROM ssr WHERE type='$_' LIMIT 0,1";
		my $sth = $paras{dbh}->prepare($sql);
		$sth->execute;
		push @{$paras{type}}, $_ if $sth->fetchrow_array;
	}
	$wdg{type}->configure(-values => $paras{type});
	
	$sql = "SELECT DISTINCT complexity FROM ssr";
	$paras{complex} = $paras{dbh}->selectcol_arrayref($sql);
	unshift @{$paras{complex}}, 'unlimited';
	$wdg{complex}->configure(-values => $paras{complex});
}
# action of function
sub import_database{
	my ($db_file) = Tkx::SplitList(shift);
	if(!$db_file){
		$db_file = Tkx::tk___getOpenFile(
			-filetypes => [['DataBase File', '.db']],
			-initialdir => $paras{last_in_dir},
		);
	}
	return unless $db_file;
	(undef, $paras{last_in_dir}) = fileparse($db_file);
	if($db_file !~ /.*\.db$/){
		alert_info("File is not SQLite database file.");
		return;
	}
	
	$paras{db} = $db_file;
	$paras{dbh} = DBI->connect("dbi:SQLite:dbname=$db_file", '', '');
	if(!$paras{dbh}){
		alert_info($DBI::errstr);
		return;
	}
	config_paras();
	$paras{sql} = "SELECT * FROM ssr";
	my $sql = $paras{sql} . " LIMIT 0,$paras{eprows}";
	my $sth = query_db_lists($sql);
	count_query_pages($paras{sql});
	create_tree_headings($sth);
	insert_to_tree($sth);
}
sub count_query_pages{
	my $sql = shift;
	$paras{trows} = query_count_rows($sql);
	$paras{csrow} = $paras{trows} ? 1 : 0;
	$paras{cerow} = ($paras{trows} > $paras{eprows}) ? $paras{eprows} : $paras{trows};
	Tkx::update();
}
sub query_db_lists{
	my $sql = shift;
	my $sth = $paras{dbh}->prepare($sql);
	if(!$sth){
		alert_info($paras{dbh}->errstr);
		return;
	}
	my $rv = $sth->execute;
	if(!$rv){
		alert_info($sth->errstr);
		return;
	}
	$paras{error} = "NO ERROR";
	return $sth;
}
sub query_count_rows{
	my $sql = shift;
	my $sth = $paras{dbh}->prepare($sql);
	$sth->execute();
	$sth->fetchall_arrayref([-1]); #fetch last row
	return $sth->rows();
}
sub alert_info{
	$paras{error} = shift;
	Tkx::update();
}
sub query_by_sql{
	if($paras{db} !~ /db$/){
		$paras{error} = 'No database file imported';
		Tkx::update();
		return;
	}
	my $sql = $wdg{sql}->get("1.0", "end");
	$sql =~ s/^\s+|\s+$//;
	return unless $sql;
	count_query_pages($sql);
	my $sth;
	if($sql =~ /limit\s+\d+\s*,/ ){
		$sth = query_db_lists($sql);
	}else{
		$sth = query_db_lists($sql. " LIMIT 0,$paras{eprows}");
	}
	$paras{sql} = $sql;
	create_tree_headings($sth);
	insert_to_tree($sth);
}
sub query_by_filter{
	if($paras{db} !~ /db$/){
		$paras{error} = 'No database file imported';
		Tkx::update();
		return;
	}
	my $sql = "SELECT * FROM ssr";
	my $filter;
	if($paras{motif} !~ /unlimited/){
		if($paras{motif_tl} eq 'Motif Type'){
			foreach (split /\s+/, $paras{motif}){
				$filter .= $filter ? " or motif='$_'" : "motif='$_'";
			}
		}else{
			$filter = "length(motif)=$paras{motif}";
		}
		$filter = "(" . $filter . ")";
	}
	if($paras{rep_min} !~ /unlimited/){
		my $rep_or_len;
		if($paras{rep_or_len} eq 'Length of SSR'){
			$rep_or_len = 'length';
		} else {
			$rep_or_len = 'repeats';
		}
		if($paras{rep_f} eq 'Between'){
			$filter .= $filter ? " and $rep_or_len BETWEEN $paras{rep_min} AND $paras{rep_max}" : "$rep_or_len BETWEEN $paras{rep_min} AND $paras{rep_max}";
		}else{
			my $sign;
			if($paras{rep_f} eq 'Equals'){
				$sign = "=";
			}elsif($paras{rep_f} eq 'Dose Not Equal'){
				$sign = "<>"
			}elsif($paras{rep_f} eq 'Less Than'){
				$sign = "<";
			}elsif($paras{rep_f} eq 'Greater Than'){
				$sign = ">";
			}
			$filter .= $filter ? " and $rep_or_len$sign$paras{rep_min}" : "$rep_or_len$sign$paras{rep_min}";
		}
	}
	if($paras{ssr_type} ne 'unlimited'){
		$filter .= $filter ? " and type='$paras{ssr_type}'" : "type='$paras{ssr_type}'";
	}
	if($paras{ssr_complex} ne 'unlimited'){
		$filter .= $filter ? " and complexity='$paras{ssr_complex}'" : "complexity='$paras{ssr_complex}'";
	}
	if($paras{ssr_origin} ne 'unlimited'){
		$filter .= $filter ? " and source='$paras{ssr_origin}'" : "source='$paras{ssr_origin}'";
	}
	$sql .= " WHERE $filter" if $filter;
	my $sth = query_db_lists($sql." LIMIT 0,$paras{eprows}");
	count_query_pages($sql);
	create_tree_headings($sth);
	insert_to_tree($sth);
	$paras{sql} = $sql;
}
sub pre_page{
	if($paras{csrow} <= 1){
		return;
	}
	$paras{cerow} = $paras{csrow} - 1;
	$paras{csrow} = $paras{csrow} - $paras{eprows};
	my $start = $paras{csrow} - 1;
	$start = 0 if $start < 0;
	my $sql = $paras{sql} . " LIMIT $start,$paras{eprows}";
	insert_to_tree(query_db_lists($sql));
	Tkx::update();
}
sub next_page{
	if($paras{cerow} == $paras{trows}){
		return;
	}
	my $sql = $paras{sql} . " LIMIT $paras{cerow},$paras{eprows}";
	insert_to_tree(query_db_lists($sql));
	$paras{csrow} = $paras{cerow} + 1;
	$paras{cerow} += $paras{eprows};
	if($paras{cerow} > $paras{trows}){
		$paras{cerow} = $paras{trows};
	}
	Tkx::update();
}
sub export_to_excel{
	my ($file, $feilds) = @_;
	my $count = 0;
	my @index = grep { $_ == $count++} @$feilds;
	my $sth = query_db_lists($paras{sql});
	my $xls = Spreadsheet::WriteExcel->new($file);
	my $i=0; #number of row
	my $j=1; #number of worksheet
	my $hws; #handle of worksheet
	while(my $ref = $sth->fetchrow_arrayref){
		if($i == 0 || $i == 65535){
			$hws=$xls->add_worksheet("worksheet$j");
			$hws->write_row(0,0, [@{$sth->{NAME}}[@index]]);
			$j++;
			$i=0;
		}
		my $seq;
		foreach (split /-/, $ref->[6]){
			if(/\(([ATGC]+)\)(\d+)/i){
				$seq .= $1 x $2;
			}else{
				$seq .= $_;
			}
		}
		
		$ref->[6] = $seq;
		
		$hws->write_row(++$i,0,[@$ref[@index]]);
	}
	$xls->close();

}
sub export_to_txt{
	my ($file, $format) = @_;
	my $sth = query_db_lists($paras{sql});
	open EXPORT, '>', $file;
	while(my $ref = $sth->fetchrow_hashref){
		my $seq;
		foreach (split /-/, $ref->{seq}){
			if(/\(([ATGC]+)\)(\d+)/i){
				$seq .= $1 x $2;
			}else{
				$seq .= $_;
			}
		}
		$ref->{seq} = $seq;
		my $output = $format;
		$output =~ s/{(\w+)}/$ref->{$1}/g;
		print EXPORT $output;
	}
	close EXPORT;
}

sub export_ssrs{
	return if $paras{trows} == 0;
	my ($wdg, $type, $file, $format, $feilds) = @_;
	if($format =~ /^\s+$/ && $type eq "TXT"){
		Tkx::tk___messageBox(
			-title => "ERROR",
			-message => "Please input output format!",
			-parent => $wdg,
		);
		return;
	}
	if($file eq ""){
		Tkx::tk___messageBox(
			-title => "ERROR",
			-message => "Please select output file!",
			-parent => $wdg,
		);
		return;
	}
	$wdg->close();
	run_status("Exporting data ...");
	if($type eq "TXT"){
		export_to_txt($file, $format);
	}else{
		export_to_excel($file, $feilds);
	}
	run_status("Export Successed!");
}

sub export_data{
	return if $paras{trows} == 0;
	my $file = Tkx::tk___getSaveFile(
		-defaultextension => '.xls',
		-initialfile => 'output',
		-initialdir => $paras{last_out_dir},
		-filetypes => [["CSV FILE",".csv"], ["EXCEL FILE",".xls"]],
	);
	return if !$file;
	my $suffix;
	(undef, $paras{last_out_dir}, $suffix) = fileparse($file, qr{\..*});
	run_status("Exporting data ...");
	my $sth = query_db_lists($paras{sql});
	if($suffix =~ /csv/){
		open CSV, ">", $file;
		print CSV join(',', @{$sth->{NAME}}), "\n";
		while(my $ref = $sth->fetchrow_arrayref){
			print CSV join(',', @$ref), "\n";
		}
		close CSV;
	}else{
		my $xls = Spreadsheet::WriteExcel->new($file);
		my $i=0; #number of row
		my $j=1; #number of worksheet
		my $hws; #handle of worksheet
		while(my $ref = $sth->fetchrow_arrayref){
			if($i == 0 || $i == 65535){
				$hws=$xls->add_worksheet("worksheet$j");
				$hws->write_row(0,0, $sth->{NAME});
				$j++;
				$i=0;
			}	
			$hws->write_row(++$i,0,$ref);
		}
		$xls->close();
	}
	run_status("Export Successed!");
}
sub export_format_ssrs{
	my ($output_file);
	return if $paras{trows} == 0;
	if ($wdg{fsw} && Tkx::winfo_exists($wdg{pw})) {
		$wdg{fsw}->display();
		Tkx::focus(-force => $wdg{pw});
		return;
    }
	$wdg{fsw} = $mw->new_widget__dialog(
		-title => 'Export SSRs',
		-padding => 4,
		-parent => $mw,
        -place => 'over',
        -modal => 'none',
		-synchronous => 0,
        -separator => 0,
    );
	my $sf = $wdg{fsw}->new_ttk__frame(
		-padding => 12,
	);
	$sf->g_grid(-sticky => 'wnes');
	$sf->g_grid_columnconfigure(1, -weight => 1);
	
	$wdg{fsw}->setwidget($sf);
	$sf->new_ttk__label(
		-text => "Select output file format:",
	)->g_grid(
		-column => 0,
		-row => 0,
		-sticky => 'e',
	);
	my $op_file_type;
	my $op_type = $sf->new_ttk__combobox(
		-state => "readonly",
		-values => ["EXCEL", "TXT"],
		-textvariable => \$op_file_type,
	);
	$op_type->g_grid(
		-sticky => "we",
		-column => 1,
		-row => 0,
	);
	
	$op_type->current(0);
	my $xf = $sf->new_ttk__frame();
	$xf->g_grid(
		-sticky => "wnes",
		-column => 0,
		-columnspan => 2,
		-row => 1,
	);
	
	$xf->new_ttk__label(
		-text => "Select ouput columns:"
	)->g_grid(
		-column => 0,
		-row => 0,
		-columnspan => 4,
		-sticky => "we",
		-pady => 10,
	);
	my ($i, $j, $k) = (1, 0, 0);
	my @feilds = ();
	foreach(qw/uid motif type complexity repeats length seq start end left right source/){
		$feilds[$k] = $k;
		if(/motif/){
			$xf->new_ttk__checkbutton(
				-text => $_,
				-variable => \$feilds[$k],
				-onvalue => $k,
				-offvalue => -1,
				-state => "disabled",
			)->g_grid(
				-column => $j++,
				-row => $i,
				-sticky => 'w',
			);
			
		}else{
			$xf->new_ttk__checkbutton(
				-text => $_,
				-variable => \$feilds[$k],
				-onvalue => $k,
				-offvalue => -1,
			)->g_grid(
				-column => $j++,
				-row => $i,
				-sticky => 'w',
			);
		}
		$k++;
		if($j == 4){
			$i++;
			$j = 0;
		}
	}
	my $of = $xf->new_ttk__frame();
	$of->g_grid(
		-column => 0,
		-row => 4,
		-columnspan => 4,
		-sticky => 'wnes',
	);
	$of->new_ttk__label(
		-text => "Select output file:",
	)->g_grid(
		-column => 0,
		-row => 0,
		-sticky => "e",
		-pady => "10 0",
	);
	$of->new_ttk__entry(
		-textvariable => \$output_file,
		-state => "disabled",
		-width => 40,
	)->g_grid(
		-column => 1,
		-row => 0,
		-sticky => "we",
		-pady => "10 0"
	);
	$of->new_ttk__button(
		-text => "Browse",
		-command => sub{
			$output_file = Tkx::tk___getSaveFile(
				-defaultextension => '.xls',
				-initialfile => 'output',
				-initialdir => $paras{last_out_dir},
				-filetypes => [["EXCEL FILE",'.xls']],
				-parent => $wdg{fsw},
			);
			return unless $output_file;
			(undef, $paras{last_out_dir}) = fileparse($output_file);
		},
	)->g_grid(
		-column => 2,
		-row => 0,
		-sticky => "e",
		-pady => "10 0",
	);

	my $tf = $sf->new_ttk__frame();

	$tf->new_ttk__label(
		-text => "Edit output format by using the tags bellow:",
	)->g_grid(
		-column => 0,
		-row => 0,
		-sticky => "we",
		-pady => 10,
	);
	$tf->new_ttk__label(
		-text => "{uid}, {motif}, {type}, {complexity}, {repeats}, {length}, {seq}, {start}, {end},\n {left}, {right}, {source}",
		-wraplength => 0,
	)->g_grid(
		-column => 0,
		-row => 1,
		-sticky => "we",
	);
	my $f_text = $tf->new_tk__text(
		-relief => "groove",
		-borderwidth => 2,
		-width => 0,
		-height => 7,
	);
	$f_text->g_grid(
		-column => 0,
		-row => 2,
		-sticky => "wnes",
		-pady => 10,
	);
	$f_text->insert("1.0", ">{source}\nMotif: {motif} Repeats: {repeats} Location: {start}-{end}\n{left}{seq}{right}");
	
	my $o_f = $tf->new_ttk__frame();
	$o_f->g_grid(
		-column => 0,
		-row => 3,
		-sticky => 'wnes',
	);
	$o_f->new_ttk__label(
		-text => "Select output file:",
	)->g_grid(
		-column => 0,
		-row => 0,
		-sticky => "e",
	);
	$o_f->new_ttk__entry(
		-textvariable => \$output_file,
		-state => "disabled",
		-width => 40,
	)->g_grid(
		-column => 1,
		-row => 0,
		-sticky => "we",
	);
	$o_f->new_ttk__button(
		-text => "Browse",
		-command => sub{
			$output_file = Tkx::tk___getSaveFile(
				-defaultextension => '.txt',
				-initialfile => 'output',
				-initialdir => $paras{last_out_dir},
				-filetypes => [["TXT FILE",'.txt']],
				-parent => $wdg{fsw},
			);
			return unless $output_file;
			(undef, $paras{last_out_dir}) = fileparse($output_file);
		},
	)->g_grid(
		-column => 2,
		-row => 0,
		-sticky => "e",
	);
	
	$sf->new_ttk__button(
		-text => "Ok",
		-command => sub{export_ssrs($wdg{fsw}, $op_file_type, $output_file, $f_text->get("1.0", "end"), \@feilds)},
	)->g_grid(
		-sticky => "e",
		-column => 0,
		-columnspan => 2,
		-row => 2,
		-pady => 10,
	);
	
	$op_type->g_bind("<<ComboboxSelected>>", sub{change_option_panel($xf, $tf, $op_file_type, \$output_file)});
	$wdg{fsw}->display();
}

sub change_option_panel{
	my ($wx, $wt, $opt, $opf) = @_;
	$$opf = "";
	if($opt eq 'EXCEL'){
		$wt->g_grid_forget();
		$wx->g_grid(-sticky => "wnes", -column => 0, -columnspan => 2, -row => 1);
	}else{
		$wx->g_grid_forget();
		$wt->g_grid(-sticky => "wnes", -column => 0, -columnspan => 2, -row => 1);
	}
}

sub export_for_primer{
	return if $paras{trows} == 0;
	my ($tag_name, $tag_val, $output_file);
	
	if ($wdg{pw} && Tkx::winfo_exists($wdg{pw})) {
		$wdg{pw}->display();
		Tkx::focus(-force => $wdg{pw});
		return;
    }
	
	$wdg{pw} = $mw->new_widget__dialog(
		-title => 'Export for primer3',
		-padding => 4,
		-parent => $mw,
        -place => 'over',
        -modal => 'none',
		-synchronous => 0,
        -separator => 0,
    );
	my $pf = $wdg{pw}->new_ttk__frame(
		-padding => 12,
	);
	$pf->g_grid(-sticky => 'wnes');
	$pf->g_grid_columnconfigure(1, -weight => 3);
	$pf->g_grid_columnconfigure(3, -weight => 1);
	$wdg{pw}->setwidget($pf);
	$pf->new_ttk__label(
		-text => "Output file:",
	)->g_grid(
		-sticky => 'e',
		-column => 0,
		-row => 0,
	);
	$pf->new_ttk__entry(
		-textvariable => \$output_file,
		-state => "disabled",
	)->g_grid(
		-sticky => 'we',
		-column => 1,
		-row => 0,
		-columnspan => 3,
	);
	$pf->new_ttk__button(
		-text => 'Browse',
		-command => sub{choose_output_file(\$output_file)},
	)->g_grid(
		-sticky => 'w',
		-column => 4,
		-row => 0,
	);
	my $tag_tree = $pf->new_ttk__treeview(
		-columns => "tag value",
		-show => 'headings',
		-selectmode => 'browse',
	);
	$tag_tree->g_grid(
		-column => 0,
		-row => 1,
		-rowspan => 7,
		-columnspan => 2,
		-sticky => 'wnes',
		-pady => "10 0",
	);
	$tag_tree->column("tag", -width => 140, -anchor => "center", -stretch => 1);
    $tag_tree->column("value", -width => 100, -anchor => "center", -stretch => 1);
	$tag_tree->heading('tag', -text => 'Tag');
    $tag_tree->heading("value", -text => 'Value');
	$tag_tree->g_bind("<<TreeviewSelect>>", sub {frech_tag_info($tag_tree, \$tag_name, \$tag_val)});
	
	my $tree_scrollbar = $pf->new_ttk__scrollbar(-orient => 'vertical', -command => [$tag_tree, 'yview']);
    $tree_scrollbar->g_grid(-column => 2, -row => 1, -rowspan => 7, -padx => "0 10", -pady => "10 0", -sticky => "ns");
    $tag_tree->configure(-yscrollcommand => [$tree_scrollbar, 'set']);
	
	
	$pf->new_ttk__label(
		-text => "Tag Name:",
	)->g_grid(
		-column => 3,
		-columnspan => 2,
		-row => 1,
		-sticky => 'we',
		-pady => "10 0",
	);
	$pf->new_ttk__entry(
		-textvariable => \$tag_name,
	)->g_grid(
		-column => 3,
		-columnspan => 2,
		-row => 2,
		-sticky => 'we',
	);
	$pf->new_ttk__label(
		-text => "Tag Value:",
	)->g_grid(
		-column => 3,
		-columnspan => 2,
		-row => 3,
		-sticky => 'we',
	);
	$pf->new_ttk__entry(
		-textvariable => \$tag_val,
	)->g_grid(
		-column => 3,
		-columnspan => 2,
		-row => 4,
		-sticky => 'we',
	);
	$pf->new_ttk__button(
		-text => "Add tag",
		-command => sub{add_tags($tag_tree, $tag_name, $tag_val)},
	)->g_grid(
		-column => 3,
		-columnspan => 2,
		-row => 5,
		-sticky => 'we',
	);
	$pf->new_ttk__button(
		-text => "Modify tag",
		-command => sub{modify_tags($tag_tree, $tag_name, $tag_val)},
	)->g_grid(
		-column => 3,
		-columnspan => 2,
		-row => 6,
		-sticky => 'we',
	);
	$pf->new_ttk__button(
		-text => "Delete tag",
		-command => sub{delete_tags($tag_tree)},
	)->g_grid(
		-column => 3,
		-columnspan => 2,
		-row => 7,
		-sticky => 'we',
	);
	$pf->new_ttk__button(
		-text => "Ok",
		-command => sub{export_primer3($tag_tree, $output_file)},
	)->g_grid(
		-column => 3,
		-columnspan => 2,
		-row => 8,
		-sticky => 'we',
	);
	$tag_tree->insert("","0", -id => "PRIMER_PRODUCT_SIZE_RANGE", -values => ["PRIMER_PRODUCT_SIZE_RANGE", "100-280"]);
	$tag_tree->insert("","0", -id => "PRIMER_MAX_END_STABILITY", -values => ["PRIMER_MAX_END_STABILITY", 250]);
	
	$wdg{pw}->display();
	Tkx::focus(-force => $wdg{pw});
}
sub export_primer3{
	my ($wdg, $output_file) = @_;
	if($output_file eq ""){
		Tkx::tk___messageBox(
			-title => "ERROR",
			-message => "Please select output file!",
			-parent => $wdg,
		);
		return;
	}
	my $tag_str;
	foreach(Tkx::SplitList($wdg->children(""))){
		$tag_str .= join("=", Tkx::SplitList($wdg->item($_, "-values")));
		$tag_str .= "\n";
	}
	$tag_str .= "=\n";
	$wdg{pw}->close();
	run_status("Exporting data for primer3 ...");
	my $sth = query_db_lists($paras{sql});
	open PRIMER, '>', $output_file;
	while(my $ref = $sth->fetchrow_hashref){
		print PRIMER "SEQUENCE_ID=".$ref->{uid}."\n";
		my $seq;
		foreach (split /-/, $ref->{seq}){
			if(/\(([ATGC]+)\)(\d+)/i){
				$seq .= $1 x $2;
			}else{
				$seq .= $_;
			}
		}
		print PRIMER "SEQUENCE_TEMPLATE=".lc($ref->{left}).uc($seq).lc($ref->{right})."\n";
		print PRIMER "SEQUENCE_TARGET=". (length($ref->{left}) + 1) . ','. $ref->{length} ."\n";
		print PRIMER $tag_str;
	}
	close PRIMER;
	run_status("Export Successed!");
}
sub add_tags{
	my ($wdg, $name, $val) = @_;
	return unless $name && $val;
	unless($wdg->exists($name)){
		$wdg->insert("", "0", -id => $name, -values => [$name, $val]);
	}
}
sub delete_tags{
	my $wdg = shift;
	$wdg->delete($wdg->selection);
}
sub modify_tags{
	my ($wdg, $name, $val) = @_;
	my $id = $wdg->selection;
	return unless $id;
	my $index = $wdg->index($id);
	$wdg->delete($id);
	$wdg->insert("", $index, -id => $name, -values => [$name, $val]);
}
sub frech_tag_info{
	my ($wdg, $name, $val) = @_;
	($$name, $$val) = Tkx::SplitList($wdg->item($wdg->selection, "-values"));
}
sub choose_output_file{
	my ($op_file) = @_;
	my $file = Tkx::tk___getSaveFile(
		-defaultextension => '.txt',
		-initialfile => 'primer_design',
		-initialdir => $paras{last_out_dir},
		-filetypes => [["TXT FILE",'.txt']],
		-parent => $wdg{pw},
	);
	return unless $file;
	(undef, $paras{last_out_dir}) = fileparse($file);
	$$op_file = $file;
}
sub run_status{
	$paras{msg} = shift;
	Tkx::update();
}
sub change_tab_bn{
	my $index = $tabs->index("current");
	if($index == 1){
		$wdg{export_bn}->configure(-state => "normal");
	}else{
		$wdg{export_bn}->configure(-state => "disabled");
	}
}
sub on_exit{
	$paras{dbh}->disconnect if defined $paras{dbh};
	$mw->g_destroy;
}