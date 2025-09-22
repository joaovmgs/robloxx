-- Grid: snap math and cell/world conversions
local Grid = {}

export type Cell = { x: number, z: number }

local function round(n: number): number
    return math.floor(n + 0.5)
end

-- Convert world position to integer cell indices given a baseOffset and cellSize
function Grid.worldToCell(pos: Vector3, baseOffset: Vector3, cellSize: number): (number, number)
    local ix = math.floor((pos.X - baseOffset.X) / cellSize) + 1
    local iz = math.floor((pos.Z - baseOffset.Z) / cellSize) + 1
    return ix, iz
end

-- Convert integer cell indices to world center position
function Grid.cellToWorldCenter(ix: number, iz: number, baseOffset: Vector3, cellSize: number, y: number): Vector3
    return Vector3.new(baseOffset.X + (ix - 0.5) * cellSize, y, baseOffset.Z + (iz - 0.5) * cellSize)
end

-- Snap an arbitrary world position to grid center (returns snapped position and indices)
function Grid.snap(pos: Vector3, baseOffset: Vector3, cellSize: number, y: number): (Vector3, number, number)
    local ix, iz = Grid.worldToCell(pos, baseOffset, cellSize)
    local snapped = Grid.cellToWorldCenter(ix, iz, baseOffset, cellSize, y)
    return snapped, ix, iz
end

-- Cell key for dictionaries/folders
function Grid.key(ix: number, iz: number): string
    return string.format("%d,%d", ix, iz)
end

return Grid

