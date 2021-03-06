{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}

module Main (main) where

import "Glob" System.FilePath.Glob (glob)
import Test.DocTest (doctest)
import Data.Monoid

import Control.Monad
import Data.Makefile
import Data.Makefile.Parse
import Data.Makefile.Render
import Test.QuickCheck
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL

instance Arbitrary Target where
  arbitrary = pure $ Target "foo"

instance Arbitrary Dependency where
  arbitrary = pure $ Dependency "bar"

instance Arbitrary Command where
  arbitrary = pure $ Command "baz"

instance Arbitrary AssignmentType where
  arbitrary =
    elements [minBound..maxBound]

instance Arbitrary Entry where
  arbitrary =
    oneof
      [ Rule <$> arbitrary <*> arbitrary <*> arbitrary
      , Assignment <$> arbitrary <*> pure "foo" <*> pure "bar"
      ]

instance Arbitrary Makefile where
  arbitrary = Makefile <$> arbitrary


main :: IO ()
main = do
    doc
    withMakefile "test-data/basic/Makefile1" $ \m -> assertTarget "foo" m
    withMakefile "test-data/basic/Makefile2" $ \m -> do
        assertTargets [ "all"
                      , "hello"
                      , "main.o"
                      , "factorial.o"
                      , "hello.o"
                      , "clean"] m
        assertAssignment ("CC", "g++") m
    withMakefile "test-data/elfparse/Makefile" $ \m -> do
        assertTargets [ "default"
                      , "is_perl_recent_enough"
                      , "all"
                      , "clean"
                      , "clean_not_caches"
                      , "${SRCP6}/STD.pmc"
                      , "lex.is_current"
                      , "${STD_BLUE_CACHEDIR}.is_current"
                      , "${STD_RED_CACHEDIR}.is_current"
                      , "IRx1_FromAST2.pm"
                      , "elfblue"
                      , "elfrx"
                      , "nodes.pm"
                      , "rx_prelude.pm"
                      , "rx_prelude_p5.pm"
                      , "std.pm.p5"
                      , "STD_green_run.pm.p5"
                      , "STD_green_run"
                      , "elfdev"
                      , "elfdev1"
                      , "check"
                      , "check_rx_on_re"
                      , "check_std_rx_on_re"
                      , "rerun_std_rx_on_re"
                      , "check_STD_blue"
                      , "does_gimme5_memory_problem_still_exist"
                      , "elfblue_regression_debug"
                      , "have_STD_red_cache"
                      , "have_STD_blue_cache" ] m
        assertAssignments [ ("ELF", "../../elf/elf_h")
                          , ("ELFDIR", "../../elf/elf_h_src")
                          , ("SRCP6", "./pugs_src_perl6")
                          , ("STDPM", "./pugs_src_perl6/STD.pm")
                          , ("TMP", "deleteme")
                          {- ... feeling lazy -} ] m
    withMakefile "test-data/basic/Makefile1" $ \m -> do
      writeMakefile  "test-data/basic/_Makefile1" m
      withMakefile "test-data/basic/_Makefile1" $ \mm -> assertMakefile m mm
    withMakefile "test-data/basic/Makefile2" $ \m -> do
      writeMakefile  "test-data/basic/_Makefile2" m
      withMakefile "test-data/basic/_Makefile2" $ \mm -> assertMakefile m mm
    withMakefileContents
      "foo = bar"
      (assertAssignments [("foo", "bar")])
    withMakefileContents "foo: bar" (assertTargets ["foo"])
    withMakefileContents
      "foo : bar"
      (assertTargets ["foo"])
    withMakefileContents
      (T.pack $ unlines
        [ "var="
        , "foo: bar"
        ]
      )
      (assertMakefile
        Makefile
          { entries =
              [ Assignment RecursiveAssign "var" ""
              , Rule "foo" ["bar"] []
              ]
          }
        )
    withMakefileContents
      (T.pack $ unlines
        [ "var=foo bar" ]
      )
      (assertAssignments [("var", "foo bar")])
    withMakefileContents
      (T.pack $ unlines
        [ "var=foo bar\\"
        , "baz"
        ]
      )
      (assertAssignments [("var", "foo bar baz")])
    withMakefileContents
      (T.pack $ unlines
        [ "var=foo bar    \\"
        , "baz"
        ]
      )
      (assertAssignments [("var", "foo bar baz")])
    withMakefileContents
      (T.pack $ unlines
        [ "var=foo bar\\"
        , "   baz"
        ]
      )
      (assertAssignments [("var", "foo bar baz")])
    withMakefileContents
      (T.pack $ unlines
        [ "var=foo bar    \\"
        , "   baz"
        ]
      )
      (assertAssignments [("var", "foo bar baz")])
    withMakefileContents
      (T.pack $ unlines
        [ "var=foo bar    \\"
        , "\tbaz"
        ]
      )
      (assertAssignments [("var", "foo bar baz")])
    withMakefileContents
      (T.pack $ unlines
        [ "var=foo bar  \t  \\"
        , "  \t  baz"
        ]
      )
      (assertAssignments [("var", "foo bar baz")])
    withMakefileContents
      (T.pack $ unlines
        [ "SUBDIRS=anna bspt cacheprof \\"
        , "        compress compress2 fem"
        ]
      )
      (assertAssignments
        [("SUBDIRS", "anna bspt cacheprof compress compress2 fem")])
    withMakefileContents
      (T.pack $ unlines
        [ "foo: anna bspt cacheprof \\"
        , "  compress compress2 fem"
        ]
      )
      (assertMakefile
        Makefile
          { entries =
              [ Rule
                  "foo"
                  [ "anna"
                  , "bspt"
                  , "cacheprof"
                  , "compress"
                  , "compress2"
                  , "fem"
                  ] []
              ]
          }
        )
    withMakefileContents
      (T.pack $ unlines
          [ "foo:"
          , "\tcd dir/ && \\"
          , "   ls"
          ]
      )
      (assertMakefile
        Makefile
          { entries =
              [ Rule "foo" [] ["cd dir/ && ls"]
              ]
          }
        )
    Success{} <- quickCheckResult prop_encodeDecode
    return ()

prop_encodeDecode :: Makefile -> Bool
prop_encodeDecode m =
  (fromRight $ parseMakefileContents $ TL.toStrict $ encodeMakefile m) == m

withMakefileContents :: T.Text -> (Makefile -> IO ()) -> IO ()
withMakefileContents contents a =
  a $ fromRight (parseMakefileContents contents)

withMakefile :: FilePath -> (Makefile -> IO ()) -> IO ()
withMakefile  f a = fromRight <$> parseAsMakefile f >>= a

assertMakefile :: Makefile -> Makefile -> IO ()
assertMakefile m1 m2 =
  unless (m1 == m2)
    $ error $ unwords
        [ "Makefiles mismatch!"
        , "got " <> show m1
        , "and " <> show m2
        ]

assertTargets :: [Target] -> Makefile -> IO ()
assertTargets ts m = mapM_ (`assertTarget` m) ts

assertAssignments :: [(T.Text, T.Text)] -> Makefile -> IO ()
assertAssignments as m = mapM_ (`assertAssignment` m) as

assertAssignment :: (T.Text, T.Text) -> Makefile -> IO ()
assertAssignment (n, v) (Makefile m) = unless (any hasAssignment m) $
    error ("Assignment " ++ show (n, v) ++ " wasn't found in Makefile " ++ show m)
  where hasAssignment (Assignment _ n' v') = n == n' && v == v'
        hasAssignment _                  = False

assertTarget :: Target -> Makefile -> IO ()
assertTarget t (Makefile m) = unless (any (hasTarget t) m) $
    error ("Target " ++ show t ++ " wasn't found in Makefile " ++ show m)
  where hasTarget t (Rule t' _ _) = t == t'
        hasTarget _ _                 = False

fromRight :: Either a b -> b
fromRight (Right x) = x
fromRight _ = error "fromRight"

doc :: IO ()
doc = glob "src/**/*.hs" >>= doctest
