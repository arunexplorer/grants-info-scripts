
# constants...ermm, sort of
${nih_data_start_year} = 1985    # it appears this is the start year in nih db - change it, if not

# variables..
${cfg_file} = ".\params.cfg"
${cfg_contents} = Get-Content ${cfg_file}
Write-Host ""
Write-Host "Configuration Used to Fetch API Results:"
${cfg_contents}
${cfg} = ${cfg_contents} | ConvertFrom-Json
Remove-Variable cfg_contents
${results_file} = ".\results.json"
Write-Host ""

# the criteria dictionary...
${criteria} = @{ }
# ${criteria}["exclude_subprojects"] = $false
# ${criteria}["sub_project_only"] = $false
# to filter using org names specified in the config file
if (${cfg}.orgs -ne $null) {
   ${criteria}["org_names"] = @()
   ${names_to_probe} = ${cfg}.orgs
   # this doesn't work, if the list has only one object, so avoid this
   #$criteria["org_names"] = ${names_to_probe} -split "; " | Where-Object {$_}
   ${names_to_probe} -split "; " | Where-Object {$_} | ForEach-Object {
      $criteria["org_names"] += $_
   }
}
# to filter using principal investigator names specified in the config file
if (${cfg}.pis -ne $null) {
   ${criteria}["pi_names"] = @()
   ${names_to_probe} = ${cfg}.pis
   ${names_to_probe} -split "; " | Where-Object {$_} | ForEach-Object {
      $name_parts = $_.split()
      $criteria["pi_names"] += @{ "first_name" = $name_parts[0]; "last_name" = $name_parts[$name_parts.count - 1] }
   }
}
# to filter using search_abstractfield text specified in the config file
if (${cfg}.search_text -ne $null) {
   ${criteria}["advanced_text_search"] = `
         @{
              "operator" = "and"
            ; "search_field" = "projecttitle,terms,abstracttext"
            ; "search_text" = ${cfg}.search_text
         }
}
Write-Host "Criteria Used to Fetch API Results: "
$criteria | ConvertTo-Json -Depth 3
#Write-Host "Press any key to continue..."
#$null = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
Write-Host ""

# initialize api_response and nih_project datasets...
${api_response} = $null
${nih_projects} = @{"results" = @()}

# process...
${year_upto} = ${cfg}.year_upto
${year_from} = ${cfg}.year_from
${use_years} = ( ${year_upto} -ne $null ) -or ( ${year_from} -ne $null )
if ( ${use_years} ) {
   if ( ${year_upto} -eq $null ) { ${year_upto} = (Get-Date).Year; }
   if ( ${year_from} -eq $null ) { ${year_from} = ${nih_data_start_year}; }
}
# iterate over the years, if years were specified, else, this loop will be executed just once as PS treats $null as 0 when used in range
${year_upto}..${year_from} | ForEach-Object {
   if ( ${use_years} ) {
      Write-Host ("`nObtaining Response for the Year: {0}" -f ${_})
   }
   ${limit_count} = ${cfg}.call_batch_size
   ${offset} = 0
   do {
      #Write-Host ("Offset Start: {0}; Limit: {1}" -f ${offset}, ${limit_count})
      #Write-Host "Press any key to continue..."
      #$null = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
      Start-Sleep -Seconds 5
      if ( ${use_years} ) {
         ${criteria}["fiscal_years"] = @( ${_} )
      }
      # invoke API endpoint...
      ${api_response} = `
         Invoke-RestMethod `
         -Headers ( @{
            "Content-Type" = "application/json"
            ; "Accept" = "application/json"
         } )`
         -Method Post `
         -Body ( @{
            "criteria" = ${criteria}
         ;   "offset" = ${offset}
         ;   "limit" = ${limit_count}
         ;   "sort_field" = "project_start_date"
         ;   "sort_order" = "desc"
         } | ConvertTo-Json -Depth 3) `
         -Uri "https://api.reporter.nih.gov/v2/projects/search"
      # use the response
      ${api_response}.meta | Format-Table
      ${nih_projects}.results += ${api_response}.results
      ${limit_count} = ${api_response}.meta.total - ${limit_count} - ${offset}
      if ( ${limit_count} -gt ${cfg}.call_batch_size ) { ${limit_count} = ${cfg}.call_batch_size }
      ${offset} += ${cfg}.call_batch_size
   } while (${limit_count} -gt 0)
}
# to filter names further, for example "Mark", use the following
#${nih_projects}.results = (${nih_projects}.results | Where-Object contact_pi_name -NotLike "*Mark*")
${nih_projects}.meta = ${api_response}.meta
if ( ${cfg}.save_results ) {
   Write-Host "Saving results into file: ${results_file}..."
   ${nih_projects} | ConvertTo-Json -Depth 4 | Out-File ${results_file}
}

# aggregate based on award_amount
${nih_projects}.results `
| Measure-Object -Property award_amount -Sum -Average -Maximum -Minimum `
| Format-Table `
     @{ label = "{0,3:n0}" -f "#s"     ; expression = { "{0,3:n0}"  -f ${_}.Count } } `
   , @{ label = "{0,14}"   -f "Sum"    ; expression = { "{0,14:n2}" -f ${_}.Sum } } `
   , @{ label = "{0,14}"   -f "Average"; expression = { "{0,14:n2}" -f ${_}.Average } } `
   , @{ label = "{0,14}"   -f "Maximum"; expression = { "{0,14:n2}" -f ${_}.Maximum } } `
   , @{ label = "{0,14}"   -f "Minimum"; expression = { "{0,14:n2}" -f ${_}.Minimum } }

# group by organization and then aggregate award_amount
${nih_projects}.results `
| Group-Object -Property { ${_}.organization.org_name } `
| Select-Object `
     @{ name = "Org"  ; expression = { ${_}.Name } } `
   , @{ name = "Count"; expression = { ${_}.Count } } `
   , @{ name = "Sum"  ; expression = { (${_}.Group | Measure-Object -Property award_amount -Sum).Sum } } `
| Sort-Object -Property Sum -Descending `
| Format-Table `
     @{ label = "{0,20}" -f "Org Name"; expression = { ${_}.Org } } `
   , @{ label = "{0,3:n0}" -f "#s"    ; expression = { "{0,3:n0}"  -f ${_}.Count } } `
   , @{ label = "{0,14}" -f "Sum"     ; expression = { "{0,14:n2}" -f ${_}.Sum } }

# group by year and then aggregate award amount
${nih_projects}.results `
| Group-Object -Property fiscal_year `
| Select-Object `
     @{ name = "Year" ; expression = { ${_}.Name } } `
   , @{ name = "Count"; expression = { ${_}.Count } } `
   , @{ name = "Sum"  ; expression = { (${_}.Group | Measure-Object -Property award_amount -Sum).Sum }  } `
| Sort-Object -Property Year -Descending `
| Format-Table `
     @{ name = "Year"            ; expression = { ${_}.Year } } `
   , @{ name = "{0,3:n0}" -f "#s"; expression = { "{0,3:n0}" -f ${_}.Count } } `
   , @{ name = "{0,14}" -f "Sum" ; expression = { "{0,14:n2}" -f ${_}.Sum } } `
   , @{ name = "{0,14}" -f "Avg" ; expression = { "{0,14:n2}" -f (${_}.Sum / ${_}.Count) } }

# group by lead and then aggregate award amount
${nih_projects}.results `
| Group-Object -Property contact_pi_name `
| Select-Object `
     @{ name = "Lead"         ; expression = { ${_}.Name } } `
   , @{ name = "Count"        ; expression = { ${_}.Count } } `
   , @{ name = "Sum"          ; expression = { (${_}.Group | Measure-Object -Property award_amount -Sum).Sum } } `
   , @{ name = "Maximum"      ; expression = { (${_}.Group | Measure-Object -Property award_amount -Maximum).Maximum } } `
   , @{ name = "Minimum"      ; expression = { (${_}.Group | Measure-Object -Property award_amount -Minimum).Minimum } } `
   , @{ name = "Organizations"; expression = { ${_}.Group.organization.org_name } } `
| Sort-Object -Property Sum -Descending `
| Format-Table `
     @{ name = "Lead"            ; expression = { ${_}.Lead } } `
   , @{ name = "{0,3:n0}" -f "#s"; expression = { "{0,3:n0}" -f ${_}.Count } } `
   , @{ name = "{0,14}" -f "Sum" ; expression = { "{0,14:n2}" -f ${_}.Sum } } `
   , @{ name = "{0,14}" -f "Max" ; expression = { "{0,14:n2}" -f ${_}.Maximum } } `
   , @{ name = "{0,14}" -f "Min" ; expression = { "{0,14:n2}" -f ${_}.Minimum } } `
   , @{ name = "{0,14}" -f "Avg" ; expression = { "{0,14:n2}" -f (${_}.Sum / ${_}.Count) } } `
   , @{ name = "Organizations"   ; expression = { ${_}.Organizations } }

# individual projects
if ( ${cfg}.show_prjs ) {
   ${nih_projects}.results `
   | Format-Table `
        appl_id `
      , @{ label = "{0,6}" -f "Active"  ; expression = { "{0,6}" -f  ( ${_}.is_active? "Yes": "No") } } `
      , @{ label = "{0,14}" -f "Amount" ; expression = { "{0,14:n2}" -f ${_}.award_amount } } `
      , @{ label = "F. Yr"              ; expression = { ${_}.fiscal_year } } `
      , @{ label = "{0,10}" -f "Start"  ; expression = { "{0:yyyy-MM-dd}" -f ${_}.project_start_date } } `
      , @{ label = "{0,10}" -f "End"    ; expression = { "{0:yyyy-MM-dd}" -f ${_}.project_end_date } } `
      , @{ label = "{0,10}" -f "Awarded"; expression = { "{0:yyyy-MM-dd}" -f ${_}.award_notice_date } } `
      , contact_pi_name `
      , @{ label = "{0,10}" -f "Title"  ;  expression = { "{0,10}" -f ( ${_}.project_title.Substring(0) ) } } `
      # TODO: check the logic on this later...
      #, @{
      #     label = "Other PI"
      #   ; expression = {
      #               (
      #                  (${_}.contact_pi_name -Notlike $criteria["pi_names"][0].last_name + "*") `
      #                  -and (${_}.principal_investigators.Count -GT 1) `
      #                  -and ((${_}.principal_investigators | Where-Object first_name -Like ("*" + $criteria["pi_names"][0].first_name + "*")).Count -EQ 1)
      #               ) ? "Yes": "No"
      #            }
      #}
}
