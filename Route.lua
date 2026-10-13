local _, ns = ...

-- Builds a loop through the given nodes on one map, starting at the node
-- nearest (px, py) when a start position is given. When there are more nodes
-- than ROUTE_MAX_NODES, the most-visited ones are kept. Returns the ordered
-- node list and loop length in yards.
function ns.BuildRoute(mapID, px, py, nodes)
    local pool = {}
    for index, node in ipairs(nodes) do
        pool[index] = node
    end
    if #pool == 0 then return {}, 0 end

    table.sort(pool, function(a, b) return a.count > b.count end)
    for i = #pool, ns.ROUTE_MAX_NODES + 1, -1 do
        pool[i] = nil
    end

    local function dist(a, b)
        return (ns.Distance(mapID, a.x, a.y, b.x, b.y))
    end

    -- Nearest-neighbour pass.
    local route = {}
    local cx, cy = px or pool[1].x, py or pool[1].y
    while #pool > 0 do
        local bestIndex, bestDistance
        for index, node in ipairs(pool) do
            local distance = ns.Distance(mapID, cx, cy, node.x, node.y)
            if not bestDistance or distance < bestDistance then
                bestIndex, bestDistance = index, distance
            end
        end
        local node = table.remove(pool, bestIndex)
        route[#route + 1] = node
        cx, cy = node.x, node.y
    end

    -- 2-opt: uncross the loop until no swap shortens it.
    local n = #route
    if n >= 4 then
        local improved, passes = true, 0
        while improved and passes < 50 do
            improved = false
            passes = passes + 1
            for i = 1, n - 2 do
                for j = i + 2, n do
                    if not (i == 1 and j == n) then
                        local a, b, c, d = route[i], route[i + 1], route[j], route[j % n + 1]
                        if dist(a, c) + dist(b, d) < dist(a, b) + dist(c, d) - 0.01 then
                            local lo, hi = i + 1, j
                            while lo < hi do
                                route[lo], route[hi] = route[hi], route[lo]
                                lo = lo + 1
                                hi = hi - 1
                            end
                            improved = true
                        end
                    end
                end
            end
        end
    end

    local length = 0
    if n >= 2 then
        for i = 1, n do
            length = length + dist(route[i], route[i % n + 1])
        end
    end
    return route, length
end
