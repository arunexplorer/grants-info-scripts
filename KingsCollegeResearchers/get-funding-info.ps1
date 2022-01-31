
# constants...
# nothing yet...

# variables..
# set the grants_url variable's value to the grantee's page
${grants_url} = "https://kclpure.kcl.ac.uk/portal/en/persons/stuart-neil(14321767-bba6-4a23-85f5-75594a182e8e)/projects.html"

# the prj list
${research_grants} = @()
${api_response} = `
   Invoke-RestMethod `
      -Headers ( @{
          "Content-Type" = "application/json"
      } )`
      -Method Get `
      -Uri "${grants_url}"

# use the response
${prj_id} = 1
foreach ( ${grant_prj} in ${api_response}.html.body.div.div[2].div[0].div[1].div.div[1].ol.li) {
   ${title} = (${grant_prj}.div.h2.a.span).Trim()
   ${period} = (${grant_prj}.div.p | Where-Object -Property class -EQ "period").span."#text"
   ${dt_start} = [datetime]::ParseExact(${period}[0], "d/M/yyyy", $null)
   ${dt_end} = [datetime]::ParseExact(${period}[1], "d/M/yyyy", $null)
   ${researchers} = [string]::Join(" | ", (${grant_prj}.div.p.a | Where-Object -Property rel -EQ "person").span)
   ${orgs} = @()
   ${org_id} = 0
   ${grant_prj}.div.p.a `
      | Where-Object -Property rel -EQ "UEOExternalOrganisation" `
      | Select-Object -ExpandProperty span `
      | % {
         ${orgs} += @{ "org_id" = ${org_id}; "name" = ${_}.Trim() }
         ${org_id} += 1
        }
   ${org_id} = 0
   (${grant_prj}.div.p | Where-Object { ${_} -like "£*" }) `
   | % {
         (${orgs} | Where-Object org_id -EQ ${org_id})["award_amt"] = [decimal](${_}.Substring(1))
         ${org_id} += 1
       }
   foreach (${org} in ${orgs}) {
      ${research_grants} += `
         @{
              "prj_id" = ${prj_id} `
            ; "title" = ${title} `
            ; "org_name" = ${org}.name `
            ; "award_amt" = ${org}.award_amt `
            ; "dt_start" = ${dt_start} `
            ; "dt_end" = ${dt_end} `
            ; "researchers" = ${researchers} `
          }
      }
      ${prj_id} += 1
}
${research_grants} = ${research_grants} | ConvertTo-Json | ConvertFrom-Json 
${research_grants} `
| Format-Table `
     @{ label = "#"                       ; expression = { ${_}.prj_id } } `
   , @{ label = "Title"                   ; expression = { ${_}.Title } } `
   , @{ label = "Organization"            ; expression = { ${_}.org_name } } `
   , @{ label = "{0,14}" -f "Award"       ; expression = { "{0,14:n2}" -f ${_}.award_amt } } `
   , @{ label = "{0,10}" -f "Start"       ; expression = { "{0:yyyy-MM-dd}" -f ${_}.dt_start } } `
   , @{ label = "{0,10}" -f "End"         ; expression = { "{0:yyyy-MM-dd}" -f ${_}.dt_end } } `
   , @{ label = "{0,50}" -f "Researchers" ; expression = { "{0,50}" -f ${_}.researchers } } `

${research_grants} `
| Measure-Object -Property award_amt -Sum -Maximum -Minimum -Average `
| Format-Table `
     @{ label = "{0,14}" -f "Sum"; expression = { "{0,14:n2}" -f ${_}.Sum } } `
   , @{ label = "{0,14}" -f "Max"; expression = { "{0,14:n2}" -f ${_}.Maximum } } `
   , @{ label = "{0,14}" -f "Min"; expression = { "{0,14:n2}" -f ${_}.Minimum } } `
   , @{ label = "{0,14}" -f "Avg"; expression = { "{0,14:n2}" -f (${_}.Sum / ${_}.Count) } }
