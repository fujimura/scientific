{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module Main where

import           Control.Applicative
import           Control.Monad
import           Data.Int
import           Data.Scientific                    as Scientific
import           Test.Tasty
import           Test.Tasty.Runners.AntXML
import           Test.Tasty.HUnit
import qualified Test.SmallCheck                    as SC
import qualified Test.SmallCheck.Series             as SC
import qualified Test.Tasty.SmallCheck              as SC  (testProperty)
import qualified Test.QuickCheck                    as QC
import qualified Test.Tasty.QuickCheck              as QC  (testProperty)
import qualified Data.Text.Lazy                     as TL  (unpack)
import qualified Data.Text.Lazy.Builder             as TLB (toLazyText)
import qualified Data.ByteString.Lazy.Char8         as BLC8
import qualified Data.ByteString.Builder.Scientific as B
import qualified Data.Text.Lazy.Builder.Scientific  as T

#if !MIN_VERSION_bytestring(0,10,2)
import qualified Data.ByteString.Lazy.Builder       as B
#else
import qualified Data.ByteString.Builder            as B
#endif

main :: IO ()
main = testMain $ testGroup "scientific"
  [ smallQuick "normalization"
       (SC.over   normalizedScientificSeries $ \s ->
            s /= 0 SC.==> abs (Scientific.coefficient s) `mod` 10 /= 0)
       (QC.forAll normalizedScientificGen    $ \s ->
            s /= 0 QC.==> abs (Scientific.coefficient s) `mod` 10 /= 0)

  , testGroup "Formatting"
    [ testProperty "read . show == id" $ \s -> read (show s) === s

    , smallQuick "toDecimalDigits_laws"
        (SC.over   nonNegativeScientificSeries toDecimalDigits_laws)
        (QC.forAll nonNegativeScientificGen    toDecimalDigits_laws)


    , testGroup "Builder"
      [ testProperty "Text" $ \s ->
          formatScientific B.Generic Nothing s ==
          TL.unpack (TLB.toLazyText $ T.formatScientificBuilder B.Generic Nothing s)

      , testProperty "ByteString" $ \s ->
          formatScientific B.Generic Nothing s ==
          BLC8.unpack (B.toLazyByteString $ B.formatScientificBuilder B.Generic Nothing s)
      ]

    , testProperty "formatScientific_fromFloatDigits" $ \(d::Double) ->
        formatScientific B.Generic Nothing (Scientific.fromFloatDigits d) ==
        show d

    -- , testProperty "formatScientific_realToFrac" $ \(d::Double) ->
    --     formatScientific B.Generic Nothing (realToFrac d :: Scientific) ==
    --     show d
    ]

  , testGroup "Num"
    [ testGroup "Equal to Rational"
      [ testProperty "fromInteger" $ \i -> fromInteger i === fromRational (fromInteger i)
      , testProperty "+"           $ bin (+)
      , testProperty "-"           $ bin (-)
      , testProperty "*"           $ bin (*)
      , testProperty "abs"         $ unary abs
      , testProperty "negate"      $ unary negate
      , testProperty "signum"      $ unary signum
      ]

    , testProperty "0 identity of +" $ \a -> a + 0 === a
    , testProperty "1 identity of *" $ \a -> 1 * a === a
    , testProperty "0 identity of *" $ \a -> 0 * a === 0

    , testProperty "associativity of +"         $ \a b c -> a + (b + c) === (a + b) + c
    , testProperty "commutativity of +"         $ \a b   -> a + b       === b + a
    , testProperty "distributivity of * over +" $ \a b c -> a * (b + c) === a * b + a * c

    , testProperty "subtracting the addition" $ \x y -> x + y - y === x

    , testProperty "+ and negate" $ \x -> x + negate x === 0
    , testProperty "- and negate" $ \x -> x - negate x === x + x

    , smallQuick "abs . negate == id"
        (SC.over   nonNegativeScientificSeries $ \x -> abs (negate x) === x)
        (QC.forAll nonNegativeScientificGen    $ \x -> abs (negate x) === x)
    ]

  , testGroup "Real"
    [ testProperty "fromRational . toRational == id" $ \x ->
        (fromRational . toRational) x === x
    ]

  , testGroup "RealFrac"
    [ testGroup "Equal to Rational"
      [ testProperty "properFraction" $ \x ->
          let (n1::Integer, f1::Scientific) = properFraction x
              (n2::Integer, f2::Rational)   = properFraction (toRational x)
          in (n1 == n2) && (f1 == fromRational f2)

      , testProperty "round" $ \(x::Scientific) ->
          (round x :: Integer) == round (toRational x)

      , testProperty "truncate" $ \(x::Scientific) ->
          (truncate x :: Integer) == truncate (toRational x)

      , testProperty "ceiling" $ \(x::Scientific) ->
          (ceiling x :: Integer) == ceiling (toRational x)

      , testProperty "floor" $ \(x::Scientific) ->
          (floor x :: Integer) == floor (toRational x)
      ]

    , testProperty "properFraction_laws" properFraction_laws

    , testProperty "round"    $ \s -> round    s == roundDefault    s
    , testProperty "truncate" $ \s -> truncate s == truncateDefault s
    , testProperty "ceiling"  $ \s -> ceiling  s == ceilingDefault  s
    , testProperty "floor"    $ \s -> floor    s == floorDefault    s
    ]

  , testGroup "Conversions"
    [ testGroup "Float"  $ conversionsProperties (undefined :: Float)
    , testGroup "Double" $ conversionsProperties (undefined :: Double)

    , testGroup "floatingOrInteger"
      [ testProperty "correct conversion" $ \s ->
            case floatingOrInteger s :: Either Double Int of
              Left  d -> d == toRealFloat s
              Right i -> i == fromInteger (coefficient s') * 10^(base10Exponent s')
                  where
                    s' = normalize s
      , testProperty "Integer == Right" $ \(i::Integer) ->
          (floatingOrInteger (fromInteger i) :: Either Double Integer) == Right i
      , smallQuick "Double == Left"
          (\(d::Double) -> isFloating d SC.==>
             (floatingOrInteger (realToFrac d) :: Either Double Integer) == Left d)
          (\(d::Double) -> isFloating d QC.==>
             (floatingOrInteger (realToFrac d) :: Either Double Integer) == Left d)
      ]
    , testGroup "floatingOrInt"
      [ testProperty "correct conversion" $ \s ->
            case floatingOrInt s :: Either Double Int of
              Left  d -> d == toRealFloat s
              Right i -> i == fromInteger (coefficient s') * 10^(base10Exponent s')
                  where
                    s' = normalize s
      , testProperty "Integer == Right" $ \(i::Int) ->
          (floatingOrInt (fromInteger $ fromIntegral i) :: Either Double Int) == Right i
      , smallQuick "Double == Left"
          (\(d::Double) -> isFloating d SC.==>
             (floatingOrInt (realToFrac d) :: Either Double Int) == Left d)
          (\(d::Double) -> isFloating d QC.==>
             (floatingOrInt (realToFrac d) :: Either Double Int) == Left d)
      ]
    ]
  , testGroup "floatingOrInt"
    [ testGroup "to Double Int64" $
      [ testCase "succ of maxBound" $
        let i = succ . fromIntegral $ (maxBound :: Int64)
            s = scientific i 0
        in (floatingOrInt s :: Either Double Int64) @?= Right 0
      , testCase "pred of minBound" $
        let i = pred . fromIntegral $ (minBound :: Int64)
            s = scientific i 0
        in (floatingOrInt s :: Either Double Int64) @?= Right 0
      ]
    ]
  ]

testMain :: TestTree -> IO ()
testMain = defaultMainWithIngredients (antXMLRunner:defaultIngredients)

isFloating :: Double -> Bool
isFloating 0 = False
isFloating d = fromInteger (floor d :: Integer) /= d

conversionsProperties :: forall realFloat.
                         ( RealFloat    realFloat
                         , QC.Arbitrary realFloat
                         , SC.Serial IO realFloat
                         , Show         realFloat
                         )
                      => realFloat -> [TestTree]
conversionsProperties _ =
  [
    -- testProperty "fromFloatDigits_1" $ \(d :: realFloat) ->
    --   Scientific.fromFloatDigits d === realToFrac d

    -- testProperty "fromFloatDigits_2" $ \(s :: Scientific) ->
    --   Scientific.fromFloatDigits (realToFrac s :: realFloat) == s

    testProperty "toRealFloat" $ \(d :: realFloat) ->
      (Scientific.toRealFloat . realToFrac) d == d

  , testProperty "toRealFloat . fromFloatDigits == id" $ \(d :: realFloat) ->
      (Scientific.toRealFloat . Scientific.fromFloatDigits) d == d

  -- , testProperty "fromFloatDigits . toRealFloat == id" $ \(s :: Scientific) ->
  --     Scientific.fromFloatDigits (Scientific.toRealFloat s :: realFloat) == s
  ]

testProperty :: (SC.Testable IO test, QC.Testable test)
             => TestName -> test -> TestTree
testProperty n test = smallQuick n test test

smallQuick :: (SC.Testable IO smallCheck, QC.Testable quickCheck)
             => TestName -> smallCheck -> quickCheck -> TestTree
smallQuick n sc qc = testGroup n
                     [ SC.testProperty "smallcheck" sc
                     , QC.testProperty "quickcheck" qc
                     ]

-- | ('==') specialized to 'Scientific' so we don't have to put type
-- signatures everywhere.
(===) :: Scientific -> Scientific -> Bool
(===) = (==)
infix 4 ===

bin :: (forall a. Num a => a -> a -> a) -> Scientific -> Scientific -> Bool
bin op a b = toRational (a `op` b) == toRational a `op` toRational b

unary :: (forall a. Num a => a -> a) -> Scientific -> Bool
unary op a = toRational (op a) == op (toRational a)

toDecimalDigits_laws :: Scientific -> Bool
toDecimalDigits_laws x =
  let (ds, e) = Scientific.toDecimalDigits x

      rule1 = n >= 1
      n     = length ds

      rule2 = toRational x == coeff * 10 ^^ e
      coeff = foldr (\di a -> a / 10 + fromIntegral di) 0 (0:ds)

      rule3 = all (\di -> 0 <= di && di <= 9) ds

      rule4 | n == 1    = True
            | otherwise = null $ takeWhile (==0) $ reverse ds

  in rule1 && rule2 && rule3 && rule4

properFraction_laws :: Scientific -> Bool
properFraction_laws x = fromInteger n + f === x        &&
                        (positive n == posX || n == 0) &&
                        (positive f == posX || f == 0) &&
                        abs f < 1
    where
      posX = positive x

      (n, f) = properFraction x :: (Integer, Scientific)

positive :: (Ord a, Num a) => a -> Bool
positive y = y >= 0

floorDefault :: Scientific -> Integer
floorDefault x = if r < 0 then n - 1 else n
                 where (n,r) = properFraction x

ceilingDefault :: Scientific -> Integer
ceilingDefault x = if r > 0 then n + 1 else n
                   where (n,r) = properFraction x

truncateDefault :: Scientific -> Integer
truncateDefault x =  m where (m,_) = properFraction x

roundDefault :: Scientific -> Integer
roundDefault x = let (n,r) = properFraction x
                     m     = if r < 0 then n - 1 else n + 1
                 in case signum (abs r - 0.5) of
                      -1 -> n
                      0  -> if even n then n else m
                      1  -> m
                      _  -> error "round default defn: Bad value"

----------------------------------------------------------------------
-- SmallCheck instances
----------------------------------------------------------------------

instance (Monad m) => SC.Serial m Scientific where
    series = scientifics

scientifics :: (Monad m) => SC.Series m Scientific
scientifics = SC.cons2 scientific

nonNegativeScientificSeries :: (Monad m) => SC.Series m Scientific
nonNegativeScientificSeries = liftM SC.getNonNegative SC.series

normalizedScientificSeries :: (Monad m) => SC.Series m Scientific
normalizedScientificSeries = liftM Scientific.normalize SC.series


----------------------------------------------------------------------
-- QuickCheck instances
----------------------------------------------------------------------

instance QC.Arbitrary Scientific where
    arbitrary = scientific <$> QC.arbitrary <*> intGen

    shrink s = zipWith scientific (QC.shrink $ Scientific.coefficient s)
                                  (QC.shrink $ Scientific.base10Exponent s)

nonNegativeScientificGen :: QC.Gen Scientific
nonNegativeScientificGen =
    scientific <$> (QC.getNonNegative <$> QC.arbitrary)
               <*> intGen

normalizedScientificGen :: QC.Gen Scientific
normalizedScientificGen = Scientific.normalize <$> QC.arbitrary

intGen :: QC.Gen Int
#if MIN_VERSION_QuickCheck(2,7,0)
intGen = QC.arbitrary
#else
intGen = QC.sized $ \n -> QC.choose (-n, n)
#endif
