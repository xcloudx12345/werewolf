{-|
Module      : Game.Werewolf.Engine
Description : Engine functions.

Copyright   : (c) Henry J. Wylde, 2015
License     : BSD3
Maintainer  : public@hjwylde.com

Engine functions.
-}

{-# LANGUAGE CPP                   #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}

module Game.Werewolf.Engine (
    -- * Loop
    advanceTurn, checkGameOver,

    -- * Game

    -- ** Manipulations
    startGame, killPlayer,

    -- ** Queries
    isSeersTurn, isVillagersTurn, isWerewolvesTurn, isGameOver, getPlayerSee, getPlayerVote,

    -- ** Reading and writing
    defaultFilePath, writeGame, readGame, deleteGame, doesGameExist,

    -- * Player

    -- ** Manipulations
    createPlayers,

    -- ** Queries
    doesPlayerExist, isPlayerSeer, isPlayerVillager, isPlayerWerewolf, isPlayerAlive, isPlayerDead,

    -- * Role
    randomiseRoles,
) where

import Control.Lens         hiding (only)
import Control.Monad.Except
import Control.Monad.Random
import Control.Monad.State  hiding (state)
import Control.Monad.Writer

import           Data.Aeson           hiding ((.=))
import qualified Data.ByteString.Lazy as BS
import           Data.List.Extra
import qualified Data.Map             as Map
import           Data.Text            (Text)

import           Game.Werewolf.Game     hiding (isGameOver, isSeersTurn, isVillagersTurn,
                                         isWerewolvesTurn, killPlayer)
import qualified Game.Werewolf.Game     as Game
import           Game.Werewolf.Player   hiding (doesPlayerExist)
import qualified Game.Werewolf.Player   as Player
import           Game.Werewolf.Response
import           Game.Werewolf.Role     as Role hiding (Villagers, Werewolves)

import System.Directory
import System.Exit
import System.FilePath
import System.Random.Shuffle

advanceTurn :: (MonadState Game m, MonadWriter [Message] m) => m ()
advanceTurn = get >>= \game -> advanceTurn' >> get >>= \game' -> unless (game == game') advanceTurn

advanceTurn' :: (MonadState Game m, MonadWriter [Message] m) => m ()
advanceTurn' = use turn >>= \turn' -> case turn' of
    Seers -> do
        seersCount <- uses players (length . filterAlive . filterSeers)
        votes'     <- use votes

        when (seersCount == Map.size votes') $ do
            forM_ (Map.toList votes') $ \(seerName, targetName) -> do
                target <- uses players (findByName_ targetName)

                tell [playerSeenMessage seerName target]

            turn .= Werewolves
            votes .= Map.empty
            tell werewolvesTurnMessages

    Werewolves -> do
        werewolvesCount <- uses players (length . filterAlive . filterWerewolves)
        votes'          <- use votes

        when (werewolvesCount == Map.size votes') $ do
            werewolfNames <- uses players (map Player._name . filterWerewolves)
            tell $ map (uncurry $ playerMadeKillVoteMessage werewolfNames) (Map.toList votes')

            turn .= Villagers
            votes .= Map.empty
            tell villagersTurnMessages

            let mTargetName = only . last $ groupSortOn (length . flip elemIndices (Map.elems votes')) (nub $ Map.elems votes')
            case mTargetName of
                Nothing         -> tell [noPlayerKilledMessage]
                Just targetName -> do
                    target <- uses players (findByName_ targetName)

                    killPlayer target
                    tell [playerKilledMessage (target ^. Player.name) (target ^. Player.role . Role.name)]

    Villagers -> do
        playersCount    <- uses players (length . filterAlive)
        votes           <- use votes

        when (playersCount == Map.size votes) $ do
            tell $ map (uncurry playerMadeLynchVoteMessage) (Map.toList votes)

            let mLynchedName = only . last $ groupSortOn (length . flip elemIndices (Map.elems votes)) (nub $ Map.elems votes)
            case mLynchedName of
                Nothing             -> tell [noPlayerLynchedMessage]
                Just lynchedName    -> do
                    target <- uses players (findByName_ lynchedName)

                    killPlayer target
                    tell [playerLynchedMessage (target ^. Player.name) (target ^. Player.role . Role.name)]

            turn .= Seers
            sees .= Map.empty
            use players >>= tell . seersTurnMessages . filterSeers

    NoOne -> return ()

only :: [a] -> Maybe a
only [a]    = Just a
only _      = Nothing

checkGameOver :: (MonadState Game m, MonadWriter [Message] m) => m ()
checkGameOver = do
    alivePlayers <- uses players filterAlive

    case length alivePlayers of
        0 -> turn .= NoOne >> tell [gameOverMessage Nothing]
        1 -> turn .= NoOne >> tell [gameOverMessage . Just $ head alivePlayers ^. Player.role . Role.name]
        _ -> return ()

startGame :: MonadError [Message] m => Text -> [Player] -> m Game
startGame callerName players = do
    when (playerNames /= nub playerNames)   $ throwError [privateMessage [callerName] "Player names must be unique."]
    when (length players < 7)               $ throwError [privateMessage [callerName] "Must have at least 7 players."]
    when (length players > 24)              $ throwError [privateMessage [callerName] "Cannot have more than 24 players."]

    return $ newGame players
    where
        playerNames = map Player._name players

killPlayer :: MonadState Game m => Player -> m ()
killPlayer player = players %= map (\player' -> if player' == player then player' & state .~ Dead else player')

isSeersTurn :: MonadState Game m => m Bool
isSeersTurn = gets Game.isSeersTurn

isVillagersTurn :: MonadState Game m => m Bool
isVillagersTurn = gets Game.isVillagersTurn

isWerewolvesTurn :: MonadState Game m => m Bool
isWerewolvesTurn = gets Game.isWerewolvesTurn

isGameOver :: MonadState Game m => m Bool
isGameOver = gets Game.isGameOver

getPlayerSee :: MonadState Game m => Text -> m (Maybe Text)
getPlayerSee playerName = use $ sees . at playerName

getPlayerVote :: MonadState Game m => Text -> m (Maybe Text)
getPlayerVote playerName = use $ votes . at playerName

defaultFilePath :: MonadIO m => m FilePath
defaultFilePath = (</> defaultFileName) <$> liftIO getHomeDirectory

defaultFileName :: FilePath
defaultFileName = ".werewolf"

readGame :: MonadIO m => m Game
readGame = liftIO $ defaultFilePath >>= BS.readFile >>= either die return . eitherDecode

writeGame :: MonadIO m => Game -> m ()
writeGame game = defaultFilePath >>= liftIO . flip BS.writeFile (encode game)

deleteGame :: MonadIO m => m ()
deleteGame = liftIO $ defaultFilePath >>= removeFile

doesGameExist :: MonadIO m => m Bool
doesGameExist = liftIO $ defaultFilePath >>= doesFileExist

createPlayers :: MonadIO m => [Text] -> m [Player]
createPlayers playerNames = zipWith newPlayer playerNames <$> randomiseRoles (length playerNames)

doesPlayerExist :: MonadState Game m => Text -> m Bool
doesPlayerExist name = uses players $ Player.doesPlayerExist name

isPlayerSeer :: MonadState Game m => Text -> m Bool
isPlayerSeer name = uses players $ isSeer . findByName_ name

isPlayerVillager :: MonadState Game m => Text -> m Bool
isPlayerVillager name = uses players $ isVillager . findByName_ name

isPlayerWerewolf :: MonadState Game m => Text -> m Bool
isPlayerWerewolf name = uses players $ isWerewolf . findByName_ name

isPlayerAlive :: MonadState Game m => Text -> m Bool
isPlayerAlive name = uses players $ isAlive . findByName_ name

isPlayerDead :: MonadState Game m => Text -> m Bool
isPlayerDead name = uses players $ isDead . findByName_ name

randomiseRoles :: MonadIO m => Int -> m [Role]
randomiseRoles n = liftIO . evalRandIO . shuffleM $ seerRoles ++ werewolfRoles ++ villagerRoles
    where
        seerRoles       = [seerRole]
        werewolfRoles   = replicate (n `quot` 6 + 1) werewolfRole
        villagerRoles   = replicate (n - length (seerRoles ++ werewolfRoles)) villagerRole
