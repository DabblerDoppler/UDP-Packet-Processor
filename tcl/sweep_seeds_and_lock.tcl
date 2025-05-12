# === CONFIGURATION ===
set project_name "header_parser"
set revision_name "header_parser"
set num_seeds 10
set lock_file "best_seed_placement.qsf"

# === INTERNAL STATE ===
set best_slack -1000
set best_seed -1

# Detect GUI mode
set running_in_gui 0
if {[info exists quartus(nameofexecutable)]} {
    set running_in_gui 1
    puts ">>> INFO: Running inside Quartus GUI Tcl Console"
} else {
    puts ">>> INFO: Running in Quartus command-line mode"
}

# === FUNCTION TO EXTRACT SLACK ===
proc get_worst_slack {project_name revision_name} {
    set tcl_file "tcl/get_slack_temp.tcl"
    set fh [open $tcl_file w]

    puts $fh "project_open $project_name -revision $revision_name"
    puts $fh {
        load_package report
        load_report
        set slack "N/A"

        set found 0
        foreach panel [get_report_panel_names] {
            puts "PANEL: $panel"
            if {$panel eq "Timing Analyzer Summary"} {
                set found 1
                set data [get_report_panel_data -name "Timing Analyzer Summary" -row 1 -col 3]
                puts "SLACK: $data"
                set slack $data
            }
        }

        if {!$found} {
            puts "WARNING: 'Timing Analyzer Summary' panel not found. Slack unavailable."
        }

        puts $slack
        project_close
    }
    close $fh

    set result [exec quartus_sta -t $tcl_file]
    file delete -force $tcl_file

    return [string trim $result]
}

# === SEED SWEEP LOOP ===
puts "\n>>> INFO: Starting seed sweep for $num_seeds seeds...\n"
for {set seed 1} {$seed <= $num_seeds} {incr seed} {
    puts "--------------------------------------------"
    puts ">>> SEED: Running seed $seed"
    puts "--------------------------------------------"

    if {!$running_in_gui} {
        puts ">>> CLEAN: Clearing database..."
        exec quartus_clean $project_name
    }

    puts ">>> STEP 1: Synthesizing..."
    exec quartus_map $project_name -c $revision_name

    puts ">>> STEP 2: Fitting seed $seed..."
    exec quartus_fit --seed=$seed $project_name -c $revision_name

    puts ">>> STEP 3: Running STA..."
    exec quartus_sta $project_name -c $revision_name

    set slack [get_worst_slack $project_name $revision_name]
    puts ">>> RESULT: Seed $seed slack = $slack"

    if {$slack != "N/A" && [expr {$slack > $best_slack}]} {
        puts ">>> UPDATE: New best seed = $seed (slack = $slack)"
        set best_slack $slack
        set best_seed $seed
    }
}

puts "\n>>> SUMMARY: Best seed is $best_seed with slack $best_slack."
puts ">>> ACTION: Re-fitting best seed and locking placement..."

# === FINAL COMPILE & LOCKING ===
puts ">>> FINAL: Re-synthesizing best seed..."
exec quartus_map $project_name -c $revision_name

puts ">>> FINAL: Re-fitting..."
exec quartus_fit --seed=$best_seed $project_name -c $revision_name

puts ">>> FINAL: STA..."
exec quartus_sta $project_name -c $revision_name

puts ">>> FINAL: Exporting assignments..."
exec quartus_cdb $project_name -c $revision_name --export_assignments=$lock_file

puts ">>> FINAL: Appending PLACEMENT_LOCK constraints..."
set fh [open $lock_file a]
puts $fh "\n# Apply placement locks"
set all_instances [get_all_instances]
foreach inst $all_instances {
    puts $fh "set_instance_assignment -name PLACEMENT_LOCK ON -to $inst"
}
close $fh

puts "\n>>> DONE: All constraints written to '$lock_file'"
puts ">>> HINT: Add this to your .qsf to reuse:\n    source $lock_file"