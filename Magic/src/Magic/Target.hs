{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE GADTs #-}

module Magic.Target (
    -- * Target lists
    TargetList(..), EntityRef(..),
    askTarget, askTarget',
    evaluateTargetList,

    -- * Constructing @TargetSpec@s
    TargetSpec(..), (<?>), orTarget,

    -- * Common @TargetSpec@s
    targetPlayer, targetInZone, targetPermanent, targetCreature, targetCreatureOrPlayer
  ) where

import qualified Magic.IdList as IdList
import Magic.Core
import Magic.Types
import Magic.Predicates
import Magic.ObjectTypes
import Magic.Some

import Control.Applicative
import Control.Monad (forM, filterM)
import Data.Boolean (true, false, (&&*))
import Data.Label.Monadic (asks)
import Data.Type.Equality (testEquality, (:~:)(..))



-- TARGET LISTS


askTarget :: PlayerRef -> TargetSpec a -> Magic (TargetList a)
askTarget p (TargetSpec cast test) = do
  ats <- allTargets
  eligibleTargets <- view $ flip filterM ats $ \t -> do
    case cast t of
      Just b -> test b
      Nothing -> false
  chosen <- askQuestion p (AskTarget eligibleTargets)
  return $ Snoc (Nil id) chosen cast test id

askTarget' :: PlayerRef -> (a -> b -> c) -> (a -> b -> View Bool) -> TargetList a -> TargetSpec b -> Magic (TargetList c)
askTarget' p combine test2 ts (TargetSpec cast test) = do
  let (_, Just a) = evaluateTargetList ts
  ats <- allTargets
  eligibleTargets <- view $ flip filterM ats $ \t -> do
    case cast t of
      Just b -> test b &&* test2 a b
      Nothing -> false
  chosen <- askQuestion p (AskTarget eligibleTargets)
  return $ Snoc ((,) <$> ts) chosen cast (uncurry test2) (uncurry combine)

allTargets :: Magic [EntityRef]
allTargets = do
  ps <- IdList.ids <$> view (asks players)
  let szrs = [Some Exile, Some Battlefield, Some Stack, Some Command] ++
            concat [ [Some (Library p), Some (Hand p), Some (Graveyard p)] | p <- ps ]
  oss <- forM szrs $ \(Some zr) -> do
    os <- IdList.ids <$> view (asks (compileZoneRef zr))
    return (map (\o -> (Some zr, o)) os)
  return (map PlayerRef ps ++ map ObjectRef (concat oss))

evaluateTargetList :: TargetList a -> ([EntityRef], Maybe a)
evaluateTargetList (Nil x) = ([], Just x)
evaluateTargetList (Snoc xs t cast _ f) = (ts ++ [t], (f .) <$> mf <*> cast t)
  where (ts, mf) = evaluateTargetList xs



-- CONSTRUCTING TARGETSPECS


data TargetSpec a where
  TargetSpec :: (EntityRef -> Maybe a) -> (a -> View Bool) -> TargetSpec a

(<?>) :: (a -> View Bool) -> TargetSpec a -> TargetSpec a
test' <?> TargetSpec cast test = TargetSpec cast (test &&* test')

orTarget :: TargetSpec a -> TargetSpec b -> TargetSpec (Either a b)
orTarget (TargetSpec cast1 test1) (TargetSpec cast2 test2) =
    TargetSpec cast3 (either test1 test2)
  where
    cast3 r =
      case cast1 r of
        Just x -> Just (Left x)
        Nothing ->
          case cast2 r of
            Just x -> Just (Right x)
            Nothing -> Nothing



-- COMMON TARGETSPECS


targetPlayer :: TargetSpec PlayerRef
targetPlayer = TargetSpec cast true
  where
    cast (PlayerRef p) = Just p
    cast _ = Nothing

targetInZone :: ZoneRef ty -> TargetSpec (ObjectRef ty)
targetInZone z = TargetSpec cast true
  where
    cast (ObjectRef (Some z', i)) =
      case testEquality z z' of
        Just Refl -> Just (z, i)
        Nothing -> Nothing
    cast _ = Nothing

targetPermanent :: TargetSpec (ObjectRef TyPermanent)
targetPermanent = targetInZone Battlefield

targetCreature :: TargetSpec (ObjectRef TyPermanent)
targetCreature = checkPermanent (hasTypes creatureType) <?> targetPermanent

targetCreatureOrPlayer :: TargetSpec (Either (ObjectRef TyPermanent) PlayerRef)
targetCreatureOrPlayer = targetCreature `orTarget` targetPlayer
