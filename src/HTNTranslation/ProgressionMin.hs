{-# LANGUAGE
    FlexibleContexts,
    ScopedTypeVariables
  #-}
module HTNTranslation.ProgressionMin (minProgression) where

import Debug.Trace

import Data.Function (on)
import Data.List
import Data.Maybe (fromMaybe)
import Data.Text (Text)

import HTNTranslation.HTNPDDL
import HTNTranslation.ProgressionBounds (findMethods, findReachableTasks')

traceShowId' :: Show a => String -> a -> a
traceShowId' t a = trace (t ++ show a) a

-- |Provides the minimum progression bound necessary for
minProgression :: forall action domain problem.
    ( HasName action
    , HasTaskHead (Maybe (Expr PDDLAtom)) action
    , HasTaskList TermExpr action
    , HasTaskOrdering action
    , HasActions action domain
    , HasTaskList TermExpr problem
    , HasTaskOrdering problem
    , Show action
    ) => domain -> problem -> (Int, [(Text, Int)])
minProgression domain problem =
    (boundsGame problem bounds, bounds)
    where
    findM :: Text -> [action]
    findM = findMethods domain
    bounds :: [(Text, Int)]
    bounds = traceShowId' "Bounds: " $
        map fst $ snd $
        until (not . fst) iterateBounds $
        (\lb -> (True, lb)) $
        map (\t -> ((t, maxBound), findM t :: [action])) $
        findReachableTasks'
            (concatMap listTaskNames . findM) $
        listTaskNames problem
    iterateBounds :: (Bool, [((Text, Int), [action])]) -> (Bool, [((Text, Int), [action])])
    iterateBounds (_, cbounds) = {-# SCC "iterateBounds" #-}
        -- traceShowId' "iterateBounds: " $
        foldl (\(changed, l) ((t, tprevb), actions) ->
                let tnextb = foldl reboundAction tprevb $ filter (isPlausible tprevb) actions in
                (changed || tnextb < tprevb, ((t, tnextb), actions) : l))
            (False, []) cbounds
        where
        ibounds :: [(Text, Int)]
        ibounds = map fst cbounds
        reboundAction :: Int -> action -> Int
        reboundAction bound action =
            min bound $ boundsGame action ibounds
        -- only consider rebounding with plausible methods (subtasks all have lower bounds)
        isPlausible :: Int -> action -> Bool
        isPlausible bound method =
            all ((< bound) . taskBound ibounds . taskName . snd)
            (enumerateTasks method :: [(Int, Expr PDDLAtom)])
    

boundsGame ::
    ( HasTaskList a tasked
    , HasTaskOrdering tasked
    ) => tasked -> [(Text, Int)] -> Int
boundsGame tasked bounds =
    {-# SCC "bounds-game" #-} minimum $ bg (max 1 $ length tasks) taskWeights
    where
    tasks :: [(Int, Text)]
    tasks = traceShowId' "tasks: " $ map (\(n, t) -> (n, taskName t)) (enumerateTasks tasked)
    taskOrdering :: [(Int, [Int])]
    taskOrdering = traceShowId' "taskOrdering: " $ map (\(t,_) -> (t, map fst $ findPrevTasks tasked t)) tasks
    taskWeights :: [(Int, Int)]
    taskWeights = traceShowId' "taskWeights: " $ map (\(n,t) -> (n, taskBound bounds t)) tasks

    -- The actual game itself
    bg :: Int -> [(Int, Int)] -> [Int]
    bg cmin [] = [cmin]
    bg cmin tn
        -- Current bound is bigger than the largest min bound plus the size of the remaining list
        | cmin >= (maximum $ map snd tn) + length tn - 1 = [cmin]
        -- Special case for completely unordered tasks
        -- | length tn == length tnc = [maximum $ map lweight $ tails $ sort $ map snd tn]
        | otherwise = (\(ccmin, ctn) -> bg (max cmin ccmin) ctn) $ tnc
        where
        tnc :: (Int, [(Int, Int)])
        tnc = progressTask tn $ minimumBy (compare `on` snd) $ unconstrained tn
    progressTask :: [(Int, Int)] -> (Int, Int) -> (Int, [(Int, Int)])
    progressTask tn t@(_,lw) =
        (lw + length tn', tn')
        where
        tn' = delete t tn
    -- Returns all tasks that do not have parents in current task network
    unconstrained :: [(Int, Int)] -> [(Int, Int)]
    unconstrained tn = traceShowId' ("unconstrained " ++ show tn ++ ": ") $
        filter ( null . intersect labels . fromMaybe [] . flip lookup taskOrdering . fst) tn
        where
        labels :: [Int]
        labels = map fst tn


taskBound :: [(Text, Int)] -> Text -> Int
taskBound bounds = fromMaybe maxBound . flip lookup bounds
