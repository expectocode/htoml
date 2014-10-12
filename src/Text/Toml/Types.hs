{-# LANGUAGE OverloadedStrings #-}

module Text.Toml.Types where

import Data.Map (Map)
import Data.List (findIndex)
import Data.Text (Text, unpack)
import Data.Time.Clock (UTCTime)
import Data.Time.Format()


-- | Type of the Toml document.
-- Differs from a 'TableNode' in that it is not "named".
-- A 'TableArray' is not possible at top level.
-- When no key-value pairs are defined on the top level,
-- it simply contains an empty 'Table'.
data TomlDoc = TomlDoc Table [TableNode]
  deriving (Eq, Ord, Show)


-- | A node in the namespace tree.
-- It is named by the 'Text' value and may contain
-- a 'Table', a 'TableArray' or 'Nothing'.
-- 'Nothing' designates that the particular name has
-- not yet been taken.
data TableNode = TableNode
    Text
    (Maybe (Either Table TableArray))
    [TableNode]
  deriving (Eq, Ord, Show)


-- | A 'Table' of key-value pairs.
type Table = Map Text Value


-- | A 'TableArray' is simply a list of 'Table's.
type TableArray = [Table]


-- Following insert* functions:
--   - build up branch arrays in reverse order, as they are reversed by the parser

-- | Insert a regular table ('Table') with the name '[Text]'.
insertT :: [Text] -> Table -> [TableNode] -> Either String [TableNode]
insertT [] _ _ = Left "Cannot call 'insertT' without a name."
insertT (name:ns) tbl nodes = case idxAndNodeWithName name nodes of
    -- Nothing with the same name at this level?
    --   sub name: append implicit node and recurse
    --   final name: append new node here
    Nothing -> if isSub
      then case insertT ns tbl [] of
             Left msg -> Left msg
             Right r  -> Right $ [TableNode name Nothing r] ++ nodes
      else Right $ [TableNode name content []] ++ nodes
    Just (idx, TableNode _ c branches) -> case c of
      -- Node exists, but not explicitly defined?
      --   sub name: recurse into existing node
      --   final name: make existing node explicit and insert content
      Nothing -> if isSub
        then case insertT ns tbl branches of
               Left msg -> Left msg
               Right r  -> Right $ replaceNode idx (TableNode name c r) nodes
        else Right $ replaceNode idx (TableNode name content branches) nodes
      -- Node has already been explicitly defined: error out
      Just _ -> Left $ "Cannot insert " ++ unpack name ++ ", as it is already defined."
  where
    content = Just . Left $ tbl  -- 'Left' designates a 'Table'
    isSub = ns /= []


-- | Insert a table array's table ('Table') with the name '[Text]'.
insertTA :: [Text] -> Table -> [TableNode] -> Either String [TableNode]
insertTA [] _ _ = Left "Cannot call 'insertTA' without a name."
insertTA (name:ns) tbl nodes = case idxAndNodeWithName name nodes of
    -- Nothing with the same name at this level?
    --   sub name: append implicit node and recurse
    --   final name: append new node here
    Nothing -> if isSub
      then case insertTA ns tbl [TableNode name Nothing []] of
             Left msg -> Left msg
             Right r  -> Right $ r ++ nodes
      else Right $ [TableNode name content []]
    Just (idx, TableNode _ c branches) -> case c of
      -- Node exists, but not explicitly defined:
      --   sub name: recurse into existing node
      --   final name: make existing node explicit and insert content
      Nothing -> if isSub
        then case insertTA ns tbl branches of
               Left msg -> Left msg
               Right r  -> Right $ replaceNode idx (TableNode name c r) nodes
        else Right $ replaceNode idx (TableNode name content branches) nodes
      Just cc -> case cc of
        -- Node explicitly defined and of type 'Table'?
        --   sub name: recurse
        --   final name: error out
        Left _ -> if isSub
          then case insertTA ns tbl branches of
                 Left msg -> Left msg
                 Right r  -> Right $ replaceNode idx (TableNode name c r) nodes
          else Left $ "Cannot insert " ++ unpack name ++ ", as it is already defined."
        -- Node explicitly defined and of type 'TableArray'?
        --   sub name: recurse
        --   final name: append to array
        Right tArray -> if isSub
          then case insertTA ns tbl branches of
                 Left msg -> Left msg
                 Right r  -> Right $ replaceNode idx (TableNode name c r) nodes
          else let newNode = TableNode name (Just . Right $ tArray ++ [tbl]) branches
               in  Right $ replaceNode idx newNode nodes
  where
    content = Just . Right $ [tbl]  -- 'Right' designates a 'TableArray'
    isSub = ns /= []


-- | Maybe get a tuple of the index and the node ('TableNode') from a 'TableNode' list.
idxAndNodeWithName :: Text -> [TableNode] -> Maybe (Int, TableNode)
idxAndNodeWithName name nodes = fmap (\i -> (i, nodes !! i)) (idxOfName name nodes)
  where
    idxOfName n = findIndex (\(TableNode nn _ _) -> n == nn)


-- | Replace the 'TableNode' from a list pointed by the index.
replaceNode :: Int -> TableNode -> [TableNode] -> [TableNode]
replaceNode idx node nodeList = concat [take idx nodeList, [node], drop (idx + 2) nodeList]


-- | The 'Value' of a key-value pair.
data Value = VString   Text
           | VInteger  Integer
           | VFloat    Double
           | VBoolean  Bool
           | VDatetime UTCTime
           | VArray    [Value]
  deriving (Eq, Ord, Show)


-- | * Restriction the value types of array elements.
--
-- The specifications below restrict the values to be
-- of the same type within an 'Array'.
--
-- The restriction is only enforced at construction,
-- in order to to complicate the types of the underlaying
-- data structures ('Table', etc.).

newtype RestrictedValue a = RV {freeValue :: Value}

restrictString :: Text -> RestrictedValue Text
restrictString = RV . VString
restrictInteger :: Integer -> RestrictedValue Integer
restrictInteger = RV . VInteger
restrictFloat :: Double -> RestrictedValue Double
restrictFloat = RV . VFloat
restrictBoolean :: Bool -> RestrictedValue Bool
restrictBoolean = RV . VBoolean
restrictDatetime :: UTCTime -> RestrictedValue UTCTime
restrictDatetime = RV . VDatetime

data Array
restrictArray :: [RestrictedValue a] -> RestrictedValue Array
restrictArray = RV . VArray . map freeValue
