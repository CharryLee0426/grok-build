// Realistic snippets (10–25 lines) used by the contact sheet, fuzz and performance tests.
enum SyntaxSamples {
    static let all: [(String, String)] = [
        ("swift", swift), ("python", python), ("javascript", javascript), ("typescript", typescript), ("tsx", tsx),
        ("rust", rust), ("go", go), ("c", c), ("cpp", cpp), ("csharp", csharp), ("java", java), ("kotlin", kotlin),
        ("scala", scala), ("objectivec", objectiveC), ("ruby", ruby), ("php", php), ("bash", bash), ("console", console),
        ("powershell", powershell), ("sql", sql), ("html", html), ("xml", xml), ("scss", scss), ("json", json),
        ("yaml", yaml), ("toml", toml), ("markdown", markdown), ("diff", diff), ("dockerfile", dockerfile),
        ("makefile", makefile), ("cmake", cmake), ("lua", lua), ("r", r), ("dart", dart), ("haskell", haskell),
        ("elixir", elixir), ("erlang", erlang), ("perl", perl), ("julia", julia), ("zig", zig), ("ocaml", ocaml),
        ("clojure", clojure), ("asm", asm), ("latex", latex), ("gitcommit", gitCommit), ("graphql", graphql),
        ("protobuf", protobuf), ("terraform", terraform), ("nix", nix), ("solidity", solidity), ("matlab", matlab),
        ("fortran", fortran), ("groovy", groovy), ("vb", visualBasic), ("nginx", nginx), ("ini", ini),
        ("dotenv", dotenv), ("vim", vim), ("fsharp", fsharp), ("scheme", scheme), ("pycon", pycon), ("vue", vue),
        ("css", css), ("jsx", jsx), ("regex", regex), ("http", http)
    ]

    static let swift = #"""
    import SwiftUI

    /// A simple counter view.
    @MainActor
    struct CounterView: View {
        @State private var count = 0
        let title: String

        var body: some View {
            VStack(spacing: 12) {
                Text("\(title): \(count)")
                    .font(.headline)
                Button("Increment") { count += 1 }
            }
            .padding()
        }
    }

    enum NetworkError: Error {
        case timeout(seconds: Double)
        case invalidURL(String)
    }

    func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard !data.isEmpty else { throw NetworkError.timeout(seconds: 3.5) }
        let raw = #"C:\path\n"#
        return try JSONDecoder().decode(T.self, from: data) // 0xFF
    }
    """#

    static let python = #"""
    from dataclasses import dataclass, field
    import asyncio

    @dataclass
    class User:
        """A user record."""
        name: str
        age: int = 0
        tags: list[str] = field(default_factory=list)

        def greet(self, greeting: str = "Hello") -> str:
            return f"{greeting}, {self.name}! You are {self.age:>3d}"

    async def main() -> None:
        users = [User("Ada", 36), User(name='Linus', age=0x1F)]
        for u in users:
            if u.age > 30 and not u.tags:
                print(u.greet(), r"\d+", b"bytes\n")
        match users:
            case [first, *_]:
                print(first)
        await asyncio.sleep(1.5e-3)  # tiny pause

    if __name__ == "__main__":
        asyncio.run(main())
    """#

    static let javascript = #"""
    import { readFile } from 'node:fs/promises';

    const API_URL = "https://api.example.com";
    const pattern = /^[a-z]+\d{2,}$/gi;

    /**
     * Fetch a user by id.
     */
    export async function getUser(id, { retries = 3 } = {}) {
      const res = await fetch(`${API_URL}/users/${id}?v=${Date.now()}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      return data?.name ?? 'anonymous';
    }

    class Cache extends Map {
      #hits = 0;
      get(key) { this.#hits++; return super.get(key); }
    }

    const total = [1, 2, 3].reduce((sum, n) => sum + n, 0) / 2;
    console.log(pattern.test("abc12"), total, 10n, null, undefined);
    """#

    static let typescript = #"""
    interface Props<T> {
      items: readonly T[];
      onSelect?: (item: T) => void;
    }

    type Status = 'idle' | 'loading' | 'error';

    enum Direction { Up = 1, Down }

    export function first<T extends object>(xs: T[]): T | undefined {
      return xs.length > 0 ? xs[0] : undefined;
    }

    const cast = <T,>(value: unknown) => value as T;

    @Component({ selector: 'app-root' })
    export class AppComponent implements OnInit {
      private readonly status: Status = 'idle';
      constructor(private http: HttpClient) {}
      ngOnInit(): void {
        const n: number = Math.max(1, 2) satisfies number;
      }
    }
    """#

    static let tsx = #"""
    import React, { useState } from "react";

    type ButtonProps = { label: string; onClick: () => void };

    export function Counter({ initial = 0 }: { initial?: number }) {
      const [count, setCount] = useState<number>(initial);
      const items = ["a", "b"].map((x) => <li key={x}>{x.toUpperCase()}</li>);
      return (
        <div className="counter" data-count={count}>
          {/* comment inside JSX */}
          <Button label={`Clicked ${count} times`} onClick={() => setCount(count + 1)} />
          <ul>{items}</ul>
          {count > 5 && <p>That&apos;s a lot!</p>}
          <>
            <span>Fragment</span>
          </>
        </div>
      );
    }
    """#

    static let jsx = #"""
    export default function App({ user }) {
      const [open, setOpen] = React.useState(false);
      if (!user) return <Spinner size="large" />;
      return (
        <Layout title={user.name}>
          <button onClick={() => setOpen(!open)} disabled={open}>
            Toggle {open ? "off" : "on"}
          </button>
          {open && <Modal onClose={() => setOpen(false)}>Hello!</Modal>}
        </Layout>
      );
    }
    """#

    static let rust = #"""
    use std::collections::HashMap;
    use std::fmt;

    #[derive(Debug, Clone, PartialEq)]
    pub struct Point<'a> {
        name: &'a str,
        x: f64,
        y: f64,
    }

    impl<'a> fmt::Display for Point<'a> {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            write!(f, "{} ({:.2}, {:.2})", self.name, self.x, self.y)
        }
    }

    fn main() -> Result<(), Box<dyn std::error::Error>> {
        let mut counts: HashMap<char, u32> = HashMap::new();
        for c in "hello".chars() {
            *counts.entry(c).or_insert(0) += 1;
        }
        let raw = r#"raw "string" \n"#;
        let bytes = b'x';
        let big = 1_000_000u64;
        println!("{:?} {} {} {}\n", counts, raw, bytes, big);
        Ok(())
    }
    """#

    static let go = #"""
    package main

    import (
    	"errors"
    	"fmt"
    	"net/http"
    )

    type Server struct {
    	Addr    string
    	handler http.Handler
    }

    var ErrClosed = errors.New("server closed")

    // Start runs the server on the given port.
    func (s *Server) Start(port int) error {
    	if port <= 0 {
    		return fmt.Errorf("invalid port: %d\n", port)
    	}
    	ch := make(chan struct{}, 1)
    	go func() { ch <- struct{}{} }()
    	raw := `C:\raw\string`
    	fmt.Println(raw, len(s.Addr), 'x', 0x1F, 3.14, nil)
    	return nil
    }
    """#

    static let c = #"""
    #include <stdio.h>
    #include <stdlib.h>
    #define MAX_ITEMS 128

    typedef struct Node {
        int value;
        struct Node *next;
    } Node;

    /* Push a value onto the list. */
    static Node *push(Node *head, int value) {
        Node *node = malloc(sizeof(Node));
        if (node == NULL) return head;
        node->value = value;
        node->next = head;
        return node;
    }

    int main(int argc, char **argv) {
        Node *list = NULL;
        for (int i = 0; i < MAX_ITEMS; i++) list = push(list, i * 2);
        printf("first=%d char=%c\n", list->value, 'A');
        return EXIT_SUCCESS; // done
    }
    """#

    static let cpp = #"""
    #include <iostream>
    #include <memory>
    #include <vector>

    namespace geo {

    template <typename T>
    class Matrix final {
    public:
        explicit Matrix(std::size_t n) : data_(n * n, T{}) {}
        [[nodiscard]] T& at(std::size_t i) noexcept { return data_[i]; }
        virtual ~Matrix() = default;
    private:
        std::vector<T> data_;
    };

    }  // namespace geo

    int main() {
        auto m = std::make_unique<geo::Matrix<double>>(3);
        constexpr auto big = 1'000'000ULL;
        const char* json = R"({"key": "value"})";
        m->at(0) = 3.14f;
        std::cout << json << ' ' << big << std::endl;
        return 0;
    }
    """#

    static let csharp = #"""
    using System;
    using System.Linq;

    namespace Demo.Services;

    [Serializable]
    public record User(string Name, int Age);

    public sealed class UserService : IUserService
    {
        private readonly List<User> _users = new();

        public async Task<User?> FindAsync(string name, CancellationToken ct = default)
        {
            await Task.Delay(10, ct);
            var match = _users.FirstOrDefault(u => u.Name == name);
            Console.WriteLine($"Found {match?.Name ?? "nobody"} at {DateTime.Now:HH:mm}");
            var path = @"C:\Users\demo";
            return match;
        }

        public int Count => _users.Count(u => u.Age > 18); // 0xFF
    }
    """#

    static let java = #"""
    package com.example.app;

    import java.util.List;
    import java.util.stream.Collectors;

    /**
     * Greets users.
     */
    @Service
    public class Greeter implements Runnable {
        private static final int MAX_USERS = 100;
        private final List<String> names;

        public Greeter(List<String> names) {
            this.names = names;
        }

        @Override
        public void run() {
            String text = """
                Hello, world!
                """;
            var upper = names.stream().map(String::toUpperCase).collect(Collectors.toList());
            System.out.printf("%s %d %c%n", text, 42L, 'x');
        }
    }
    """#

    static let kotlin = #"""
    package com.example

    import kotlinx.coroutines.*

    data class User(val name: String, val age: Int = 0)

    sealed interface Result<out T> {
        data class Ok<T>(val value: T) : Result<T>
        object Loading : Result<Nothing>
    }

    @JvmStatic
    fun String.shout(): String = uppercase() + "!"

    suspend fun main() = coroutineScope {
        val users = listOf(User("Ada", 36), User("Linus"))
        val adults = users.filter { it.age >= 18 }
        launch {
            delay(1_000L)
            println("Adults: ${adults.size}, first=$adults ${'x'}")
        }
        when (val r: Result<Int> = Result.Ok(42)) {
            is Result.Ok -> println(r.value)
            else -> println("loading")
        }
    }
    """#

    static let scala = #"""
    import scala.concurrent.{ExecutionContext, Future}

    case class Point(x: Double, y: Double)

    object Main extends App {
      val points = List(Point(1, 2), Point(3.5, 4))
      def norm(p: Point): Double = math.sqrt(p.x * p.x + p.y * p.y)

      points.map(norm).foreach(n => println(s"norm = $n, ${n * 2}"))

      val result = points match {
        case Nil => "empty"
        case head :: _ => f"first: ${head.x}%.2f"
      }
      // TODO: async
      implicit val ec: ExecutionContext = ExecutionContext.global
    }
    """#

    static let objectiveC = #"""
    #import <Foundation/Foundation.h>

    @interface Person : NSObject
    @property (nonatomic, copy) NSString *name;
    @property (nonatomic, assign) NSInteger age;
    - (instancetype)initWithName:(NSString *)name age:(NSInteger)age;
    @end

    @implementation Person

    - (instancetype)initWithName:(NSString *)name age:(NSInteger)age {
        self = [super init];
        if (self) {
            _name = [name copy];
            _age = age;
        }
        return self;
    }

    - (NSString *)description {
        return [NSString stringWithFormat:@"%@ (%ld)", self.name, (long)self.age];
    }

    @end
    """#

    static let ruby = #"""
    require 'json'

    module Shop
      class Order < ApplicationRecord
        attr_accessor :items, :status
        TAX_RATE = 0.08

        def initialize(items = [])
          @items = items
          @status = :pending
        end

        def total
          subtotal = items.sum { |i| i[:price] * i.fetch(:qty, 1) }
          (subtotal * (1 + TAX_RATE)).round(2)
        end

        def paid? = status == :paid

        def summary
          <<~TEXT
            Order with #{items.size} items
            Total: #{total}
          TEXT
        end
      end
    end

    order = Shop::Order.new([{ price: 9.99, qty: 2 }])
    puts order.summary if order.total > 10 && "abc" =~ /b+/
    """#

    static let php = #"""
    <?php
    declare(strict_types=1);

    namespace App\Http\Controllers;

    use Illuminate\Http\Request;

    #[Route('/users')]
    final class UserController extends Controller
    {
        private const PER_PAGE = 20;

        // List users
        public function index(Request $request): array
        {
            $name = $request->input('name', "guest");
            $users = User::where('active', true)->paginate(self::PER_PAGE);
            echo "Hello, {$name}! You have $count items\n";
            return ['users' => $users, 'total' => count($users)];
        }
    }
    ?>
    <p class="footer">Rendered at <?= date('Y-m-d') ?></p>
    """#

    static let bash = #"""
    #!/usr/bin/env bash
    set -euo pipefail

    # Deploy the app
    APP_DIR="${HOME}/apps/$1"
    readonly VERSION=1.2.3

    log() { echo "[$(date +%H:%M:%S)] $*" >&2; }

    if [[ ! -d "$APP_DIR" ]]; then
      mkdir -p "$APP_DIR" && cd "$APP_DIR"
    fi

    for file in *.tar.gz; do
      tar -xzf "$file" --strip-components=1
    done

    case "$ENV" in
      prod) npm run build -- --mode production ;;
      *)    echo "dev build: $# args, exit=$?" ;;
    esac

    cat <<EOF > config.env
    VERSION=$VERSION
    EOF
    """#

    static let console = #"""
    $ npm install --save-dev typescript
    added 1 package, and audited 2 packages in 1s
    found 0 vulnerabilities
    $ npx tsc --version
    Version 5.4.5
    user@macbook:~/project$ git status --short
     M src/index.ts
    ?? notes.md
    (venv) $ python -m pytest -q tests/ # run tests
    ....                                                  [100%]
    4 passed in 0.12s
    """#

    static let powershell = #"""
    # Clean up old logs
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [int]$Days = 30
    )

    $cutoff = (Get-Date).AddDays(-$Days)
    Get-ChildItem -Path $Path -Filter *.log -Recurse |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -WhatIf

    function Get-Greeting([string]$Name) {
        return "Hello, $Name! Today is $(Get-Date -Format 'dddd')"
    }

    if ($env:CI -eq $true) { Write-Host "Running in CI" -ForegroundColor Green }
    [System.IO.File]::WriteAllText("$Path\out.txt", (Get-Greeting 'Ada'))
    """#

    static let sql = #"""
    -- Top customers by revenue
    WITH recent_orders AS (
        SELECT customer_id, SUM(total) AS revenue
        FROM orders
        WHERE created_at >= NOW() - INTERVAL '30 days'
          AND status <> 'cancelled'
        GROUP BY customer_id
    )
    select c.name, r.revenue, rank() over (order by r.revenue desc) as position
    from customers c
    inner join recent_orders r on r.customer_id = c.id
    where c.email like '%@example.com' and c.deleted_at is null
    order by r.revenue desc
    limit 10;

    CREATE TABLE IF NOT EXISTS audit_log (
        id BIGSERIAL PRIMARY KEY,
        payload JSONB NOT NULL DEFAULT '{}',
        created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
    );
    """#

    static let html = #"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>Demo &amp; Test</title>
      <style>
        body { font-family: system-ui, sans-serif; margin: 0 auto; }
        .card:hover { color: #3366ff; }
      </style>
    </head>
    <body>
      <!-- Main content -->
      <main id="app" class="container" data-ready>
        <h1>Hello, world</h1>
        <button type="button" onclick="greet()">Greet</button>
      </main>
      <script>
        function greet() {
          const name = prompt("Name?");
          alert(`Hello, ${name}!`);
        }
      </script>
    </body>
    </html>
    """#

    static let xml = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleIdentifier</key>
        <string>com.example.app</string>
        <key>LSMinimumSystemVersion</key>
        <string>14.0</string>
        <!-- Permissions -->
        <key>NSCameraUsageDescription</key>
        <string>Used to scan &quot;codes&quot;</string>
        <key>Enabled</key>
        <true/>
        <data><![CDATA[raw <data>]]></data>
    </dict>
    </plist>
    """#

    static let scss = #"""
    @use 'sass:math';

    $primary: #3366ff;
    $radius: 8px !default;

    .card {
      display: flex;
      padding: math.div(16px, 2) 1.5rem;
      border-radius: $radius;
      background: linear-gradient(to right, rgba(0, 0, 0, 0.5), transparent);

      &:hover > .title::after {
        color: darken($primary, 10%);
        content: "→";
      }

      @media (max-width: 600px) {
        flex-direction: column !important;
      }
    }

    #main a[href^="https"] { text-decoration: underline; } // links
    """#

    static let css = #"""
    :root {
      --accent: #0a84ff;
      --radius: 12px;
    }

    /* Buttons */
    .btn, button[type="submit"] {
      color: var(--accent);
      border: 1px solid currentColor;
      transition: opacity 0.2s ease-in-out;
      background: url(images/bg.png) no-repeat;
    }

    @keyframes fade { from { opacity: 0 } to { opacity: 1 } }
    """#

    static let json = #"""
    {
      "name": "grok-desktop",
      "version": "1.4.0",
      "private": true,
      "scripts": {
        "build": "tsc -p . && vite build",
        "test": "vitest --run"
      },
      "engines": { "node": ">=18" },
      "keywords": ["ai", "chat", "desktop"],
      "maxTokens": 4096,
      "temperature": 0.7,
      "escape": "line\nbreak \u00e9",
      "parent": null
    }
    """#

    static let yaml = #"""
    # GitHub Actions workflow
    name: CI
    on:
      push:
        branches: [main, "release/*"]
      pull_request:

    env:
      NODE_VERSION: 20
      DEBUG: false

    jobs:
      test:
        runs-on: ${{ matrix.os }}
        steps:
          - uses: actions/checkout@v4
          - name: Test
            run: |
              npm test -- --coverage
              echo "done"
    defaults: &defaults
      retries: 3
    production:
      <<: *defaults
      url: 'https://example.com'
    """#

    static let toml = #"""
    # Cargo manifest
    [package]
    name = "syntaxkit"
    version = "0.1.0"
    edition = "2021"
    authors = ["Ada <ada@example.com>"]

    [dependencies]
    serde = { version = "1.0", features = ["derive"] }
    tokio = { version = "1", default-features = false }

    [profile.release]
    lto = true
    opt-level = 3

    [[bin]]
    name = "cli"
    path = 'src/main.rs'
    released = 2024-05-01T10:00:00Z
    """#

    static let markdown = #"""
    ---
    title: Release Notes
    draft: false
    ---

    # Version 2.0

    Some **bold** text, some *italic*, and `inline code`.

    ## Features

    - [x] Syntax highlighting for [40+ languages](https://example.com/docs)
    - [ ] Theme support
    1. Numbered item with ~~strikethrough~~

    > Note: this is a blockquote.

    ```swift
    let greeting = "Hello"
    print(greeting)
    ```

    | Language | Status |
    |----------|:------:|
    | Swift    | done   |
    """#

    static let diff = #"""
    diff --git a/src/app.js b/src/app.js
    index 3b18e51..a9c2f4d 100644
    --- a/src/app.js
    +++ b/src/app.js
    @@ -1,7 +1,8 @@ function main() {
     const express = require('express');
    -const port = 3000;
    +const port = process.env.PORT || 3000;
    +const host = '0.0.0.0';

     app.get('/', (req, res) => {
    -  res.send('Hello');
    +  res.send('Hello, world');
     });
    \ No newline at end of file
    """#

    static let dockerfile = #"""
    # syntax=docker/dockerfile:1
    FROM node:20-alpine AS builder
    ARG APP_ENV=production
    ENV NODE_ENV=$APP_ENV \
        PORT=8080
    WORKDIR /app
    COPY package*.json ./
    RUN --mount=type=cache,target=/root/.npm \
        npm ci && npm run build
    COPY --from=builder /app/dist ./dist
    EXPOSE 8080/tcp
    HEALTHCHECK --interval=30s CMD curl -f http://localhost:${PORT}/health || exit 1
    USER node
    CMD ["node", "dist/server.js"]
    """#

    static let makefile = """
    # Build settings
    CC ?= clang
    CFLAGS := -O2 -Wall -Wextra
    SRC := $(wildcard src/*.c)
    OBJ := $(patsubst src/%.c,build/%.o,$(SRC))

    .PHONY: all clean test

    all: build/app

    build/app: $(OBJ)
    \t@mkdir -p $(dir $@)
    \t$(CC) $(CFLAGS) -o $@ $^

    build/%.o: src/%.c
    \t$(CC) $(CFLAGS) -c $< -o $@

    clean:
    \trm -rf build # remove outputs
    """

    static let cmake = #"""
    cmake_minimum_required(VERSION 3.20)
    project(SyntaxDemo VERSION 1.0 LANGUAGES CXX)

    set(CMAKE_CXX_STANDARD 20)
    option(BUILD_TESTS "Build unit tests" ON)

    # Library
    add_library(core STATIC src/core.cpp src/util.cpp)
    target_include_directories(core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)

    if(BUILD_TESTS AND NOT WIN32)
      enable_testing()
      add_executable(tests test/main.cpp)
      target_link_libraries(tests PRIVATE core)
      message(STATUS "Tests enabled for ${PROJECT_NAME}")
    endif()
    """#

    static let lua = #"""
    -- Simple class
    local Account = {}
    Account.__index = Account

    function Account.new(owner, balance)
      local self = setmetatable({}, Account)
      self.owner = owner
      self.balance = balance or 0
      return self
    end

    function Account:deposit(amount)
      if amount <= 0 then error("invalid amount") end
      self.balance = self.balance + amount
    end

    local acc = Account.new("Ada", 100)
    acc:deposit(50.5)
    print(string.format("%s has %.2f", acc.owner, acc.balance), #acc.owner ~= 0, nil)
    local long = [[multi
    line]]
    --[[ block
    comment ]]
    """#

    static let r = #"""
    library(dplyr)
    library(ggplot2)

    # Summarise by group
    summary_df <- mtcars %>%
      group_by(cyl) %>%
      summarise(mean_mpg = mean(mpg, na.rm = TRUE), n = n())

    plot_mpg <- function(df, title = "MPG by cylinders") {
      ggplot(df, aes(x = factor(cyl), y = mean_mpg)) +
        geom_col(fill = "steelblue") +
        labs(title = title)
    }

    if (nrow(summary_df) > 0L && !is.na(summary_df$mean_mpg[1])) {
      print(plot_mpg(summary_df))
    }
    x <- c(1.5, 2, NA, Inf)
    """#

    static let dart = #"""
    import 'package:flutter/material.dart';

    class CounterPage extends StatefulWidget {
      const CounterPage({super.key, required this.title});
      final String title;

      @override
      State<CounterPage> createState() => _CounterPageState();
    }

    class _CounterPageState extends State<CounterPage> {
      int _count = 0;

      void _increment() => setState(() => _count++);

      @override
      Widget build(BuildContext context) {
        return Scaffold(
          appBar: AppBar(title: Text('${widget.title}: $_count')),
          floatingActionButton: FloatingActionButton(onPressed: _increment),
        );
      }
    }
    """#

    static let haskell = #"""
    {-# LANGUAGE OverloadedStrings #-}
    module Main where

    import qualified Data.Map as Map
    import Data.List (sortBy)

    -- | A simple binary tree
    data Tree a = Leaf | Node (Tree a) a (Tree a)
      deriving (Show, Eq)

    insert :: Ord a => a -> Tree a -> Tree a
    insert x Leaf = Node Leaf x Leaf
    insert x t@(Node l v r)
      | x < v     = Node (insert x l) v r
      | x > v     = Node l v (insert x r)
      | otherwise = t

    main :: IO ()
    main = do
      let tree = foldr insert Leaf [5, 3, 8, 1 :: Int]
          xs' = map (* 2) [1..10]
      print tree >> print (sum xs', 'c', "done")
    """#

    static let elixir = #"""
    defmodule Shop.Cart do
      @moduledoc """
      Shopping cart operations.
      """
      alias Shop.{Item, Repo}

      @tax 0.08

      def total(%{items: items} = cart, opts \\ []) do
        items
        |> Enum.map(fn %Item{price: p, qty: q} -> p * q end)
        |> Enum.sum()
        |> apply_tax(Keyword.get(opts, :tax, @tax))
      end

      defp apply_tax(amount, rate) when is_number(rate), do: Float.round(amount * (1 + rate), 2)

      def valid?(cart), do: cart.items != [] and not is_nil(cart.user_id)

      def greet(name), do: IO.puts("Hello, #{name}!")
      def pattern, do: ~r/^[a-z]+$/i
    end
    """#

    static let erlang = #"""
    -module(counter).
    -export([start/0, loop/1]).

    %% Start a counter process
    start() ->
        spawn(?MODULE, loop, [0]).

    loop(Count) ->
        receive
            {increment, From} ->
                From ! {ok, Count + 1},
                loop(Count + 1);
            stop ->
                io:format("stopped at ~p~n", [Count]);
            _Other ->
                loop(Count)
        after 5000 ->
            timeout
        end.
    """#

    static let perl = #"""
    #!/usr/bin/perl
    use strict;
    use warnings;

    my %ages = (alice => 31, bob => 27);
    my @names = sort keys %ages;

    sub greet {
        my ($name, $greeting) = @_;
        $greeting //= "Hello";
        return "$greeting, $name!\n";
    }

    foreach my $name (@names) {
        print greet($name) if $ages{$name} > 18;
    }

    my $text = "2024-05-01";
    if ($text =~ m/^(\d{4})-(\d\d)/) {
        (my $clean = $text) =~ s/-/\//g;
        print "Year: $1, clean: $clean\n";
    }
    my @words = qw(apple banana cherry);
    """#

    static let julia = #"""
    using LinearAlgebra

    """
        normalize_rows(A)

    Return a copy of `A` with unit-norm rows.
    """
    function normalize_rows(A::AbstractMatrix{T}) where {T<:Real}
        B = similar(A, Float64)
        for i in axes(A, 1)
            row = @view A[i, :]
            B[i, :] = row ./ norm(row)
        end
        return B
    end

    A = [1.0 2.0; 3.0 4.0]'
    println("Norms: $(norm.(eachrow(normalize_rows(A))))")
    @time sum(abs2, A)
    x = :symbol; c = 'x'; push!(v, 1e-3)
    """#

    static let zig = #"""
    const std = @import("std");

    const Point = struct {
        x: f32,
        y: f32,

        pub fn length(self: Point) f32 {
            return @sqrt(self.x * self.x + self.y * self.y);
        }
    };

    pub fn main() !void {
        const stdout = std.io.getStdOut().writer();
        var list = std.ArrayList(u8).init(std.heap.page_allocator);
        defer list.deinit();
        const p = Point{ .x = 3.0, .y = 4.0 };
        try stdout.print("length = {d:.2}\n", .{p.length()});
        const msg =
            \\multi-line
            \\string literal
        ;
        _ = msg;
        if (list.items.len == 0) return error.Empty;
    }
    """#

    static let ocaml = #"""
    (* Binary tree operations *)
    type 'a tree =
      | Leaf
      | Node of 'a tree * 'a * 'a tree

    let rec insert x = function
      | Leaf -> Node (Leaf, x, Leaf)
      | Node (l, v, r) as t ->
        if x < v then Node (insert x l, v, r)
        else if x > v then Node (l, v, insert x r)
        else t

    let () =
      let t = List.fold_left (fun acc x -> insert x acc) Leaf [5; 3; 8] in
      Printf.printf "%s %c %d\n" "done" 'x' (List.length [1; 2])
    """#

    static let fsharp = #"""
    module Demo

    open System

    /// A shape
    type Shape =
        | Circle of radius: float
        | Rect of width: float * height: float

    [<EntryPoint>]
    let main argv =
        let area = function
            | Circle r -> Math.PI * r ** 2.0
            | Rect (w, h) -> w * h
        let shapes = [ Circle 1.0; Rect (2.0, 3.5) ]
        shapes |> List.iter (fun s -> printfn $"Area: {area s:F2}")
        0 // exit code
    """#

    static let clojure = #"""
    (ns demo.core
      (:require [clojure.string :as str]))

    ;; Compute word frequencies
    (defn word-freq
      "Returns a map of word -> count."
      [text & {:keys [min-count] :or {min-count 1}}]
      (->> (str/split (str/lower-case text) #"\s+")
           (frequencies)
           (filter (fn [[_ n]] (>= n min-count)))
           (into {})))

    (def ^:dynamic *verbose* false)

    (defmacro unless [test & body]
      `(if (not ~test) (do ~@body)))

    (println (word-freq "a b a" :min-count 2) \a 3/4 nil)
    """#

    static let scheme = #"""
    ; Classic recursion
    (define (factorial n)
      (if (<= n 1)
          1
          (* n (factorial (- n 1)))))

    (define-syntax swap!
      (syntax-rules ()
        ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))

    #| block
       comment |#
    (display (map (lambda (x) (* x x)) '(1 2 3)))
    (newline)
    (list #t #f #\a "text" 'sym 3.14)
    """#

    static let asm = #"""
    ; Hello world for Linux x86-64
    section .data
        msg     db  "Hello, world!", 10
        len     equ $ - msg

    section .text
        global _start

    _start:
        mov     rax, 1          ; sys_write
        mov     rdi, 1          ; stdout
        lea     rsi, [rel msg]
        mov     rdx, len
        syscall
    .exit:
        xor     edi, edi
        mov     eax, 0x3c       ; sys_exit
        syscall
    """#

    static let latex = #"""
    \documentclass[11pt]{article}
    \usepackage{amsmath}

    % Custom command
    \newcommand{\R}{\mathbb{R}}

    \begin{document}
    \section{Introduction}
    Let $f : \R \to \R$ be defined by $f(x) = x^2 + 1$. Then
    \begin{equation}
      \int_0^1 f(x)\,dx = \frac{4}{3}.
      \label{eq:integral}
    \end{equation}
    See Equation~\eqref{eq:integral} and \textbf{Theorem 1}. Costs 50\%.
    \end{document}
    """#

    static let gitCommit = #"""
    feat(parser)!: support nested fenced code blocks

    Nested fences inside Markdown blocks are now highlighted with the
    language named in their info string.

    Closes #42
    Signed-off-by: Ada Lovelace <ada@example.com>
    # Please enter the commit message for your changes.
    # On branch main
    """#

    static let graphql = #"""
    # Fetch a user with posts
    query GetUser($id: ID!, $first: Int = 10) {
      user(id: $id) {
        id
        name
        posts(first: $first, orderBy: {field: CREATED_AT, direction: DESC}) @include(if: true) {
          edges { node { title } }
        }
        ...UserFields
      }
    }

    type User implements Node {
      id: ID!
      email: String @deprecated(reason: "Use contact")
    }

    fragment UserFields on User { email }
    """#

    static let protobuf = #"""
    syntax = "proto3";

    package demo.v1;

    import "google/protobuf/timestamp.proto";

    // A user account.
    message User {
      string id = 1;
      string display_name = 2;
      repeated string tags = 3;
      map<string, int64> counters = 4;
      google.protobuf.Timestamp created_at = 5;
      enum Role { ROLE_UNSPECIFIED = 0; ROLE_ADMIN = 1; }
      Role role = 6 [deprecated = true];
    }

    service UserService {
      rpc GetUser(GetUserRequest) returns (User);
    }
    """#

    static let terraform = #"""
    terraform {
      required_version = ">= 1.5"
    }

    variable "region" {
      type    = string
      default = "us-west-2"
    }

    # Web server
    resource "aws_instance" "web" {
      ami           = data.aws_ami.ubuntu.id
      instance_type = var.instance_type
      count         = 2
      tags = {
        Name = "web-${count.index}"
        Env  = local.env
      }
      user_data = <<-EOT
        #!/bin/bash
        echo "hello"
      EOT
    }

    output "ips" { value = aws_instance.web[*].public_ip }
    """#

    static let nix = #"""
    { pkgs ? import <nixpkgs> {} }:

    let
      version = "1.2.0";
      src = ./src;
    in pkgs.stdenv.mkDerivation rec {
      pname = "hello-app";
      inherit version src;
      buildInputs = with pkgs; [ openssl zlib ];
      # Build phase
      buildPhase = ''
        make PREFIX=$out VERSION=${version}
      '';
      meta.description = "Demo package";
      doCheck = true;
    }
    """#

    static let solidity = #"""
    // SPDX-License-Identifier: MIT
    pragma solidity ^0.8.20;

    import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

    contract Token is ERC20 {
        uint256 public constant MAX_SUPPLY = 1_000_000 ether;
        mapping(address => bool) private minters;

        event Minted(address indexed to, uint256 amount);

        constructor() ERC20("Demo", "DMO") {}

        function mint(address to, uint256 amount) external {
            require(minters[msg.sender], "not a minter");
            require(totalSupply() + amount <= MAX_SUPPLY);
            _mint(to, amount);
            emit Minted(to, amount);
        }
    }
    """#

    static let matlab = #"""
    % Compute and plot a damped sine
    function y = damped(t, tau)
        %DAMPED Damped sine wave.
        if nargin < 2
            tau = 0.5;
        end
        y = exp(-t ./ tau) .* sin(2*pi*t);
    end

    t = linspace(0, 5, 500)';
    y = damped(t);
    plot(t, y, 'LineWidth', 2);
    title("Damped sine");
    A = [1 2; 3 4]';
    disp(['max: ', num2str(max(y))]);
    """#

    static let fortran = #"""
    program heat
      implicit none
      integer, parameter :: n = 100
      real(kind=8) :: u(n), dx
      integer :: i

      ! initial condition
      dx = 1.0d0 / real(n - 1, 8)
      do i = 1, n
         u(i) = sin(3.14159d0 * (i - 1) * dx)
      end do

      if (maxval(u) > 0.5 .and. .not. isnan(u(1))) then
         print *, 'max value:', maxval(u)
      end if
    end program heat
    """#

    static let groovy = #"""
    plugins {
        id 'org.jetbrains.kotlin.jvm' version '1.9.22'
        id 'application'
    }

    group = 'com.example'
    version = "1.0.${buildNumber ?: 0}"

    repositories { mavenCentral() }

    dependencies {
        implementation 'com.squareup.okhttp3:okhttp:4.12.0'
        testImplementation "org.junit.jupiter:junit-jupiter:5.10.0"
    }

    tasks.register('hello') {
        doLast { println "Hello from ${project.name}" }
    }
    """#

    static let visualBasic = #"""
    Imports System.Text

    Module Program
        ' Entry point
        Sub Main(args As String())
            Dim names As New List(Of String) From {"Ada", "Linus"}
            For Each name As String In names
                If name.Length > 3 AndAlso Not String.IsNullOrEmpty(name) Then
                    Console.WriteLine($"Hello, {name}!")
                End If
            Next
            Dim total As Integer = Sum(1, 2)
        End Sub

        Function Sum(a As Integer, b As Integer) As Integer
            Return a + b
        End Function
    End Module
    """#

    static let nginx = #"""
    # Reverse proxy
    server {
        listen 443 ssl http2;
        server_name example.com www.example.com;

        ssl_certificate /etc/ssl/certs/example.pem;
        client_max_body_size 10m;

        location / {
            proxy_pass http://127.0.0.1:3000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        location ~* \.(png|jpg|css|js)$ {
            expires 30d;
            access_log off;
        }
    }
    """#

    static let ini = #"""
    ; Application settings
    [database]
    host = localhost
    port = 5432
    user = "admin"
    enabled = true

    [logging]
    level = debug   ; verbose
    path = /var/log/app.log
    """#

    static let dotenv = #"""
    # Local environment
    export DATABASE_URL=postgres://localhost:5432/app
    API_KEY="sk-test-123"
    DEBUG=true
    PORT=8080
    LOG_DIR=${HOME}/logs
    """#

    static let vim = #"""
    " Basic settings
    set number relativenumber
    set tabstop=4 shiftwidth=4 expandtab
    let g:mapleader = ","

    nnoremap <leader>w :w<CR>
    autocmd FileType python setlocal colorcolumn=88

    function! s:Trim() abort
      let l:save = winsaveview()
      keeppatterns %s/\s\+$//e
      call winrestview(l:save)
    endfunction
    """#

    static let pycon = #"""
    >>> import math
    >>> def area(r):
    ...     return math.pi * r ** 2
    ...
    >>> area(2)
    12.566370614359172
    >>> area("x")
    Traceback (most recent call last):
      File "<stdin>", line 1, in <module>
    TypeError: can't multiply sequence by non-int of type 'float'
    """#

    static let vue = #"""
    <template>
      <div class="todo" :class="{ done: item.done }">
        <input v-model="text" @keyup.enter="add" placeholder="New task" />
        <li v-for="item in items" :key="item.id">{{ item.title.toUpperCase() }}</li>
      </div>
    </template>

    <script setup lang="ts">
    import { ref } from 'vue'
    const text = ref<string>('')
    const add = () => items.value.push({ id: Date.now(), title: text.value })
    </script>

    <style scoped>
    .todo { padding: 8px; }
    </style>
    """#

    static let regex = #"""
    ^(?<user>[\w.+-]+)@(?:[a-z0-9-]+\.)+[a-z]{2,}$|\d{3}-\d{4}\b
    """#

    static let http = #"""
    POST /api/v1/messages HTTP/1.1
    Host: api.example.com
    Content-Type: application/json
    Authorization: Bearer {{token}}

    {
      "model": "grok-4",
      "messages": [{"role": "user", "content": "Hi"}],
      "stream": true
    }
    """#
}
