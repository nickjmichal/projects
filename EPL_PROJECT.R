#Nick Michal
library(tidyverse)
library(lubridate)

EPL_Standings <- function(uDate, season) {
  #convert date using lubridate
  uDate <- mdy(uDate)
  #Get data depending on set selected
  if(season == "2020/21") {
    eplData <- read.csv(url("http://www.football-data.co.uk/mmz4281/2021/E0.csv"))
    eplData <- eplData[,c(2,4:8)]
  } else if (season == "2019/20") {
    eplData <- read.csv(url("http://www.football-data.co.uk/mmz4281/1920/E0.csv"))
    eplData <- eplData[,c(2,4:8)]
  } else if (season == "2018/19") {
    eplData <- read.csv(url("http://www.football-data.co.uk/mmz4281/1819/E0.csv"))
    eplData <- eplData[,c(2:7)]
  }
  
  #make a subset for home team data
  homeTeamWLD <- eplData %>%
    mutate(formattedDate = dmy(Date)) %>%
    filter(uDate >= formattedDate) %>%
    group_by(TeamName = HomeTeam)
  
  #summarize home team data based on wins/losses/draws/goals
  homeTeamWLD <- summarize(homeTeamWLD, 
                           homeWinCount = sum(FTR == 'H'),
                           homeLossCount = sum(FTR == 'A'),             
                           homeDrawCount = sum(FTR == 'D'),
                           homeGoals = sum(FTHG),
                           homeGoalsAllowed = sum(FTAG)
                           )
  
  #make a subset for away team data
  awayTeamWLD <- eplData %>%
    mutate(formattedDate = dmy(Date)) %>%
    filter(uDate >= formattedDate) %>%
    group_by(TeamName = AwayTeam)
  
  #summarize away team data based on wins/losses/draws/goals
  awayTeamWLD <- summarize(awayTeamWLD, 
                           awayWinCount = sum(FTR == 'A'),
                           awayLossCount = sum(FTR == 'H'),             
                           awayDrawCount = sum(FTR == 'D'),
                           awayGoals = sum(FTHG),
                           awayGoalsAllowed = sum(FTAG)
  )
  
  #merge homeTeamWLD and awayTeamWLD
  combinedWLD <- merge(homeTeamWLD, awayTeamWLD, by = 'TeamName')
  
  #calculate team stats
  combinedWLD <- mutate(combinedWLD, 
                        Record = paste0((homeWinCount + awayWinCount),"-", (homeLossCount + awayLossCount), "-", (homeDrawCount + awayDrawCount)),
                        HomeRec = paste0(homeWinCount, "-", homeLossCount, "-", homeDrawCount),
                        AwayRec = paste0(awayWinCount, "-", awayLossCount, "-", awayDrawCount),
                        MatchesPlayed = paste(homeWinCount + awayWinCount + homeLossCount + awayLossCount + homeDrawCount + awayDrawCount),
                        Points = paste((homeWinCount * 3) + homeDrawCount + awayDrawCount),
                        PPM = paste(round(((homeWinCount * 3) + homeDrawCount + awayDrawCount) / (homeWinCount + awayWinCount + homeLossCount + awayLossCount + homeDrawCount + awayDrawCount), digits = 2)),
                        PtPct = paste(round(((homeWinCount * 3) + homeDrawCount + awayDrawCount) / (3 * (homeWinCount + awayWinCount + homeLossCount + awayLossCount + homeDrawCount + awayDrawCount)), digits = 2)),
                        GS = paste(homeGoals + awayGoals),
                        GSM = paste(round((homeGoals = awayGoals) / (homeWinCount + awayWinCount + homeLossCount + awayLossCount + homeDrawCount + awayDrawCount), digits = 2)),
                        GA = paste(homeGoalsAllowed + awayGoalsAllowed),
                        GAM = paste(round((homeGoalsAllowed = awayGoalsAllowed) / (homeWinCount + awayWinCount + homeLossCount + awayLossCount + homeDrawCount + awayDrawCount), digits = 2))
  )
  
#Section to handle Last10 record ---------------------------------------------
  #get streak data for home team
  homeTeamStreak <- eplData %>%
    mutate(formattedDate = dmy(Date)) %>%
    filter(uDate >= formattedDate) %>%
    group_by(TeamName = HomeTeam, formattedDate)
  
  #summarize home team data by win/loss/draw
  homeTeamStreak <- summarize(homeTeamStreak, result = if(FTHG > FTAG) {'W'}
                              else if (FTAG > FTHG) {'L'}
                              else {'D'})
  
  #get streak data for away team
  awayTeamStreak <- eplData %>%
    mutate(formattedDate = dmy(Date)) %>%
    filter(uDate >= formattedDate) %>%
    group_by(TeamName = AwayTeam, formattedDate)
  
  #summarize away team data by win/loss/draw
  awayTeamStreak <- summarize(awayTeamStreak, result = if(FTHG < FTAG) {'W'}
                              else if (FTAG < FTHG) {'L'}
                              else {'D'})
  
  #append away data to home data
  combinedStreak <- rbind(homeTeamStreak, awayTeamStreak)
  #set as new dataframe so I can manipulate but use combinedStreak later
  currentRecord <- combinedStreak
  #get latest 10 games
  currentRecord <- currentRecord %>%
    mutate(formattedDate) %>%
    group_by(TeamName) %>%
    arrange(desc(formattedDate)) %>% #sort descending by date to get last 10 games
    slice(1:10) #found this one on stackoverflow
  
  #make dataframe with TeamName and their record
  currentRecord <- summarize(currentRecord,
                             W = sum(result == 'W'),
                             L = sum(result == 'L'),
                             D = sum(result == 'D')
  )
  
  #set "Last10"
  currentRecord <- mutate(currentRecord, Last10 = paste0(W, "-", L, "-", D))
  
  #section to handle team streak -----------------------------------
  #set dataframe for 1 row for each team
  teamStreak <- combinedStreak[,c(1)] %>%
    group_by(TeamName)
  teamStreak <- summarize(teamStreak)
  #add columns for counting streaks and their type
  teamStreak <- mutate(teamStreak, streakCount = TeamName, streakType = TeamName)

  #loop though each team and get their streak count and type
  for(i in 1:length(teamStreak$TeamName)) {
    #set temp dataframe to hold loop results
    tempStreak <- combinedStreak %>%
    filter(TeamName == teamStreak$TeamName[i]) %>%
    arrange(desc(formattedDate))

    #set streakCount and streakType and add to dataframe
    streakCount <- rle(tempStreak$result)[1][1] #Thanks Google for rle()!
    streakCount <- head(unlist(streakCount), n=1)
    streakType <- rle(tempStreak$result)[2][1]
    streakType <- head(unlist(streakType), n=1)
    teamStreak$streakCount <- gsub(teamStreak$TeamName[i], streakCount, teamStreak$streakCount, fixed = TRUE)
    teamStreak$streakType <- gsub(teamStreak$TeamName[i], streakType, teamStreak$streakType, fixed = TRUE)
    
    if(teamStreak$streakType[i] == "D") { teamStreak$streakType[i] <- "T" } #Change "D" to "T" as per instructions
    }
  #set "Streak"
  teamStreak <- mutate(teamStreak, Streak = paste0(streakType, streakCount))
  
#Section for combining dataframes into final results ------------------------
  #combine all sections into one dataframe
  oneAndTwo <- merge(combinedWLD, currentRecord, by = 'TeamName')
  allSections <- merge(oneAndTwo, teamStreak, by = 'TeamName')
  
  #sort by Points, PPM, Wins, Goals Scored, then ascending by Goals Allowed
  allSections <- allSections[order(desc(allSections$Points), desc(allSections$PPM), desc(allSections$homeWinCount + allSections$awayWinCount), desc(allSections$homeGoals + allSections$awayGoals), (allSections$homeGoalsAllowed + allSections$awayGoalsAllowed)),]
  
  #pick columns and return final results
  return(allSections[,c(1,12:22,26,29)])
 }

EPL_Standings("04/25/2020", "2019/20")
