{-# LANGUAGE OverloadedStrings #-}

module Lib
  ( someFunc
  ) where

import           Data.Aeson
import           Data.Attoparsec.Text          as AP
import qualified Data.Map                      as Map
import           Data.Shogi.StdTypes
import qualified Data.Text                     as T
import           Data.TextIO
import           Data.TextIO.IO                ()
import           Data.TextIO.Network
import           LibLSSP.Comps.Base
import           LibLSSP.Comps.GameCommunicate
import           LibLSSP.Comps.RuleConsensus
import           LibLSSP.DataFormats.Json
import           LibLSSP.Parsers.Base
import           LibLSSP.Parsers.Connect
import           LibLSSP.Parsers.RuleConsensus
import           LibLSSP.Senders.Base
import           LibLSSP.Senders.Connect
import           LibLSSP.Senders.GameStart
import           LibLSSP.Senders.RuleConsensus
import           TextShow
import Data.Shogi.Board

commandPrefix :: AP.Parser T.Text
commandPrefix = AP.takeWhile (/= ':') <* lexeme (AP.char ':')

getCommandPrefix :: T.Text -> Maybe T.Text
getCommandPrefix tx = AP.maybeResult $ AP.parse commandPrefix tx

getCPrefixM :: T.Text -> T.Text -> TextIO T.Text
getCPrefixM name tx = case getCommandPrefix tx of
  Just pref -> if pref == name
    then return pref
    else throwParseError tx >> return ""
  Nothing   -> throwParseError tx >> return ""

getCRLF :: TextIO T.Text
getCRLF = do
  x <- getCh
  xs <- if x == '\r' then getCRLF' else getCRLF
  return $ T.cons x xs
  where
    getCRLF' = do
      x <- getCh
      if x == '\n'
        then return $ T.singleton x
        else do
          xs <- getCRLF
          return $ T.cons x xs

jsonCommand :: ToJSON a => T.Text -> a -> T.Text
jsonCommand pref v = withend $ pref
  `T.append` ": <- LSSP-JSON/1.0.0\r\n"
  `T.append` encodeText v
  `T.append` "\r\n"

throwParseError :: T.Text -> TextIO ()
throwParseError tx = throwText $ "This is illegal command: " `T.append` tx

initialConC :: StdShogiComp -> InitialContext
initialConC scomp = InitialContext True board hands
  where
    board = map (\i -> map (\j -> lookupOnBoard i j $ onboard scomp) [1..9]) [1..9]

    hands = onhands scomp

phase1 :: TextIO ()
phase1 = do
  pstr <- getTextLine
  tx <- getCPrefixM "Protocol" pstr
  putText $ allowDataFormatsCommand []
  pstr <- getTextLine
  tx <- getCPrefixM "Rule-Intension" pstr
  return ()

phase2 :: InitialContext -> TextIO ()
phase2 ic = do
  putText $ ruleModeCommand Declaration
  putText $ ruleDeclarationCommand $ RuleDeclarationInfo "standard" (Version3 1 0 0)
  putText $ jsonCommand "Initial-Context" ic
  pstr <- getTextLine
  tx <- getCPrefixM "Rule-Consensus" pstr
  return ()

phase3 :: TextIO ()
phase3 = do
  putText $ isReadyCommand "to game"
  pstr <- getTextLine
  tx <- getCPrefixM "Ready-Game" pstr
  return ()

phase4 :: TextIO ()
phase4 = putText $ gameStartCommand "good luck"

phase5 :: GameContext -> TextIO ()
phase5 gc = do
  putText $ gameStartCommand "good luck"
  putText $ gameStartCommand "good luck"

serverIO :: TextIO ()
serverIO = do
  let context = GameContext True Nothing Nothing [] [] Map.empty
  phase1
  phase2 $ initialConv context
  phase3
  phase4

someFunc :: IO ()
someFunc = runTIOTCPServer (serverSettings 4000 "*") serverIO