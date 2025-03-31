package utils;

import haxe.ds.Map;
import haxe.ds.IntMap;
import haxe.ds.List;

// Point typedef for A* pathfinding
typedef Point = { x: Int, y: Int };

private class Node {
    public var x: Int;
    public var y: Int;
    public var g: Float; // Cost from start to current node
    public var h: Float; // Heuristic cost from current node to end
    public var f: Float; // Total cost (g + h)
    public var parent: Null<Node>;

    public function new(x: Int, y: Int, ?g: Float = 0, ?h: Float = 0, ?parent: Null<Node> = null) {
        this.x = x;
        this.y = y;
        this.g = g;
        this.h = h;
        this.f = g + h;
        this.parent = parent;
    }
}

class AStar {
    private var grid: Array<Array<Int>>;
    private var rows: Int;
    private var cols: Int;

    public function new(grid: Array<Array<Int>>) {
        this.grid = grid;
        this.rows = grid.length;
        this.cols = grid[0].length;
    }

    public static function findPath(grid: Array<Array<Int>>, start: Point, end: Point): Null<Array<Point>> {
        var astar = new AStar(grid);
        return astar.findPathInternal(start, end);
    }

    private function findPathInternal(start: Point, end: Point): Null<Array<Point>> {
        var openList = new List<Node>();
        var closedList = new Map<String, Bool>();
        var startNode = new Node(start.x, start.y);
        var endNode = new Node(end.x, end.y);

        openList.add(startNode);

        while (!openList.isEmpty()) {
            var currentNode = getLowestFCostNode(openList);
            openList.remove(currentNode);
            closedList.set('${currentNode.x},${currentNode.y}', true);

            if (currentNode.x == endNode.x && currentNode.y == endNode.y) {
                return reconstructPath(currentNode);
            }

            var neighbors = getNeighbors(currentNode);
            for (neighbor in neighbors) {
                if (closedList.exists('${neighbor.x},${neighbor.y}')) {
                    continue;
                }

                var tentativeGCost = currentNode.g + 1;
                var inOpenList = false;
                for (node in openList) {
                    if (node.x == neighbor.x && node.y == neighbor.y) {
                        inOpenList = true;
                        if (tentativeGCost < node.g) {
                            node.g = tentativeGCost;
                            node.f = node.g + node.h;
                            node.parent = currentNode;
                        }
                        break;
                    }
                }

                if (!inOpenList) {
                    neighbor.g = tentativeGCost;
                    neighbor.h = heuristic(neighbor, endNode);
                    neighbor.f = neighbor.g + neighbor.h;
                    neighbor.parent = currentNode;
                    openList.add(neighbor);
                }
            }
        }

        return null; // No path found
    }

    private function getLowestFCostNode(list: List<Node>): Node {
        var lowestFNode = list.first();
        for (node in list) {
            if (node.f < lowestFNode.f) {
                lowestFNode = node;
            }
        }
        return lowestFNode;
    }

    private function getNeighbors(node: Node): Array<Node> {
        var neighbors = new Array<Node>();
        var directions = [
            {x: -1, y: 0}, {x: 1, y: 0},
            {x: 0, y: -1}, {x: 0, y: 1}
        ];

        for (dir in directions) {
            var newX = node.x + dir.x;
            var newY = node.y + dir.y;

            if (isValidPosition(newX, newY) && grid[newY][newX] == 0) {
                neighbors.push(new Node(newX, newY));
            }
        }

        return neighbors;
    }

    private function isValidPosition(x: Int, y: Int): Bool {
        return x >= 0 && x < cols && y >= 0 && y < rows;
    }

    private function heuristic(node: Node, end: Node): Float {
        return Math.abs(node.x - end.x) + Math.abs(node.y - end.y);
    }

    private function reconstructPath(endNode: Node): Array<Point> {
        var path = new Array<Point>();
        var current = endNode;

        while (current != null) {
            path.unshift({x: current.x, y: current.y});
            current = current.parent;
        }

        return path;
    }
}
