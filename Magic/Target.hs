{-# LANGUAGE RankNTypes #-}

module Magic.Target (
    -- * Types
    TargetList(..), Target(..),

    -- * Producing target lists
    singleTarget, (<?>),

    -- * Compiling target lists
    evaluateTargetList, askMagicTargets
  ) where

import qualified Magic.IdList as IdList
import Magic.Core
import Magic.Types

import Control.Applicative
import Control.Monad (forM, filterM)
import Data.Label.PureM (asks)


evaluateTargetList :: TargetList Target a -> ([Target], a)
evaluateTargetList (Nil x)       = ([], x)
evaluateTargetList (Snoc xs t)   = (ts ++ [t], f t) where (ts, f) = evaluateTargetList xs
evaluateTargetList (Test f _ xs) = (ts,        f x) where (ts, x) = evaluateTargetList xs

singleTarget :: TargetList () Target
singleTarget = Snoc (Nil id) ()

infixl 4 <?>
(<?>) :: TargetList t a -> (a -> View Bool) -> TargetList t a
xs <?> ok = Test id ok xs

askTargets :: forall a. ([Target] -> Magic Target) -> [Target] -> TargetList () a -> Magic (TargetList Target a)
askTargets choose = askTargets' (const (return True))
  where
    askTargets' :: forall b. (b -> View Bool) -> [Target] -> TargetList () b -> Magic (TargetList Target b)
    askTargets' ok ts scheme =
      case scheme of
        Nil x -> return (Nil x)
        Snoc xs () -> do
          xs' <- askTargets choose ts xs
          let (_, f) = evaluateTargetList xs'
          eligibleTargets <- view (filterM (ok . f) ts)
          chosen <- choose eligibleTargets
          return (Snoc xs' chosen)
        Test f ok' scheme' -> do
          z <- askTargets' (\x -> (&&) <$> ok (f x) <*> ok' x) ts scheme'
          return (f <$> z)

askMagicTargets :: PlayerRef -> TargetList () a -> Magic (TargetList Target a)
askMagicTargets p ts = do
  ats <- allTargets
  askTargets (liftQuestion p . AskTarget) ats ts

allTargets :: Magic [Target]
allTargets = do
  ps <- IdList.ids <$> view (asks players)
  let zrs = [Exile, Battlefield, Stack, Command] ++
            [ z p | z <- [Library, Hand, Graveyard], p <- ps ]
  oss <- forM zrs $ \zr -> do
    os <- IdList.ids <$> view (asks (compileZoneRef zr))
    return (map (\o -> (zr, o)) os)
  return (map TargetPlayer ps ++ map TargetObject (concat oss))

