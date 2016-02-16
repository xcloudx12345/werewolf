{-|
Module      : Werewolf.Commands.Poison
Description : Options and handler for the poison subcommand.

Copyright   : (c) Henry J. Wylde, 2015
License     : BSD3
Maintainer  : public@hjwylde.com

Options and handler for the poison subcommand.
-}

module Werewolf.Commands.Poison (
    -- * Options
    Options(..),

    -- * Handle
    handle,
) where

import Control.Monad.Except
import Control.Monad.Extra
import Control.Monad.State
import Control.Monad.Writer

import Data.Text (Text)

import Game.Werewolf.Command
import Game.Werewolf.Engine
import Game.Werewolf.Response

data Options = Options
    { argTarget :: Text
    } deriving (Eq, Show)

handle :: MonadIO m => Text -> Options -> m ()
handle callerName (Options targetName) = do
    unlessM doesGameExist $ exitWith failure
        { messages = [noGameRunningMessage callerName]
        }

    game <- readGame

    let command = poisonCommand callerName targetName

    case runExcept (runWriterT $ execStateT (apply command >> checkStage >> checkGameOver) game) of
        Left errorMessages      -> exitWith failure { messages = errorMessages }
        Right (game', messages) -> writeGame game' >> exitWith success { messages = messages }
