{-|
Module      : Werewolf.Options
Description : Optparse utilities.

Copyright   : (c) Henry J. Wylde, 2015
License     : BSD3
Maintainer  : public@hjwylde.com

Optparse utilities.
-}

{-# LANGUAGE OverloadedStrings #-}

module Werewolf.Options (
    -- * Options
    Options(..), Command(..),

    -- * Optparse
    werewolfPrefs, werewolfInfo, werewolf,
) where

import           Data.List.Extra
import           Data.Text       (Text)
import qualified Data.Text       as T
import           Data.Version    (showVersion)

import qualified Werewolf.Commands.Choose    as Choose
import qualified Werewolf.Commands.Help      as Help
import qualified Werewolf.Commands.Interpret as Interpret
import qualified Werewolf.Commands.Poison    as Poison
import qualified Werewolf.Commands.Protect   as Protect
import qualified Werewolf.Commands.See       as See
import qualified Werewolf.Commands.Start     as Start
import qualified Werewolf.Commands.Vote      as Vote
import qualified Werewolf.Version            as This

import Options.Applicative

-- | Options.
data Options = Options
    { optCaller  :: Text
    , argCommand :: Command
    } deriving (Eq, Show)

-- | Command.
data Command
    = Choose Choose.Options
    | End
    | Heal
    | Help Help.Options
    | Interpret Interpret.Options
    | Pass
    | Ping
    | Poison Poison.Options
    | Protect Protect.Options
    | Quit
    | See See.Options
    | Start Start.Options
    | Status
    | Version
    | Vote Vote.Options
    deriving (Eq, Show)

-- | The default preferences.
--   Limits the help output to 100 columns.
werewolfPrefs :: ParserPrefs
werewolfPrefs = prefs $ columns 100

-- | An optparse parser of a werewolf command.
werewolfInfo :: ParserInfo Options
werewolfInfo = info (infoOptions <*> werewolf) (fullDesc <> header' <> progDesc')
    where
        infoOptions = helper <*> version
        version     = infoOption ("Version " ++ showVersion This.version) $ mconcat
            [ long "version", short 'V', hidden
            , help "Show this binary's version"
            ]

        header'     = header "A game engine for running werewolf in a chat client."
        progDesc'   = progDesc $ unwords
            [ "This engine is based off of Werewolves of Millers Hollow"
            , "(http://www.games-wiki.org/wiki/Werewolves_of_Millers_Hollow/)."
            , "See https://github.com/hjwylde/werewolf for help on writing chat interfaces."
            ]

-- | An options parser.
werewolf :: Parser Options
werewolf = Options
    <$> fmap T.pack (strOption $ mconcat
        [ long "caller", metavar "PLAYER"
        , help "Specify the calling player's name"
        ])
    <*> subparser (mconcat
        [ command "choose"      $ info (helper <*> choose)      (fullDesc <> progDesc "Choose an allegiance")
        , command "end"         $ info (helper <*> end)         (fullDesc <> progDesc "End the current game")
        , command "heal"        $ info (helper <*> heal)        (fullDesc <> progDesc "Heal the devoured player")
        , command "help"        $ info (helper <*> help_)       (fullDesc <> progDesc "Help documents")
        , command "interpret"   $ info (helper <*> interpret)   (fullDesc <> progDesc "Interpret a command" <> noIntersperse)
        , command "pass"        $ info (helper <*> pass)        (fullDesc <> progDesc "Pass")
        , command "ping"        $ info (helper <*> ping)        (fullDesc <> progDesc "Pings the status of the current game publicly")
        , command "poison"      $ info (helper <*> poison)      (fullDesc <> progDesc "Poison a player")
        , command "protect"     $ info (helper <*> protect)     (fullDesc <> progDesc "Protect a player")
        , command "quit"        $ info (helper <*> quit)        (fullDesc <> progDesc "Quit the current game")
        , command "see"         $ info (helper <*> see)         (fullDesc <> progDesc "See a player's allegiance")
        , command "start"       $ info (helper <*> start)       (fullDesc <> progDesc "Start a new game")
        , command "status"      $ info (helper <*> status)      (fullDesc <> progDesc "Get the status of the current game")
        , command "version"     $ info (helper <*> version)     (fullDesc <> progDesc "Show this engine's version")
        , command "vote"        $ info (helper <*> vote)        (fullDesc <> progDesc "Vote against a player")
        ])

choose :: Parser Command
choose = Choose . Choose.Options . T.pack <$> strArgument (metavar "ALLEGIANCE")

end :: Parser Command
end = pure End

heal :: Parser Command
heal = pure Heal

help_ :: Parser Command
help_ = Help . Help.Options
    <$> optional (subparser $ mconcat
        [ command "commands"    $ info (pure Help.Commands)     (fullDesc <> progDesc "Print the in-game commands")
        , command "description" $ info (pure Help.Description)  (fullDesc <> progDesc "Print the game description")
        , command "rules"       $ info (pure Help.Rules)        (fullDesc <> progDesc "Print the game rules")
        , command "roles"       $ info (pure Help.Roles)        (fullDesc <> progDesc "Print the roles and their descriptions")
        ])

interpret :: Parser Command
interpret = Interpret . Interpret.Options <$> many (
    T.pack <$> strArgument (metavar "-- COMMAND ARG...")
    )

pass :: Parser Command
pass = pure Pass

ping :: Parser Command
ping = pure Ping

poison :: Parser Command
poison = Poison . Poison.Options <$> playerArgument

protect :: Parser Command
protect = Protect . Protect.Options <$> playerArgument

quit :: Parser Command
quit = pure Quit

see :: Parser Command
see = See . See.Options <$> playerArgument

start :: Parser Command
start = fmap Start $ Start.Options
    <$> fmap (map T.pack . wordsBy (',' ==)) (strOption $ mconcat
        [ long "extra-roles", metavar "ROLE,..."
        , value []
        , help "Specify the extra roles to include"
        ])
    <*> many (T.pack <$> strArgument (metavar "PLAYER..."))

status :: Parser Command
status = pure Status

version :: Parser Command
version = pure Version

vote :: Parser Command
vote = Vote . Vote.Options <$> playerArgument

playerArgument :: Parser Text
playerArgument = T.pack <$> strArgument (metavar "PLAYER")
