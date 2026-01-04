const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

/// Represents a blog post with its metadata and content
/// - title: The extracted title from the post's first H1 heading
/// - content: The HTML-converted content from markdown
/// - directory: The relative path where the post is located
/// - filename: The original markdown filename
const Post = struct {
    title: []const u8,
    content: []const u8,
    directory: []const u8,
    filename: []const u8,
};

/// The main site generator that handles converting markdown to HTML
/// and building the complete static site structure
const SiteGenerator = struct {
    allocator: Allocator, // Memory allocator for dynamic allocations
    posts: ArrayList(Post), // Collection of all parsed posts
    dir_path: []const u8, // Base directory path for the site
    template: []const u8, // HTML template for wrapping content

    /// Initialize a new SiteGenerator with the given allocator and directory path
    /// - Sets up the posts ArrayList
    /// - Creates the default HTML template with placeholders
    /// Returns a configured SiteGenerator or an error
    pub fn init(allocator: Allocator, dir_path: []const u8) !SiteGenerator {
        const posts: ArrayList(Post) = .{};

        // Define the HTML template with placeholders:
        // - {{root_path}}: Will be replaced with relative path to site root
        // - {{title}}: Will be replaced with page title
        // - {{content}}: Will be replaced with page content
        const default_template =
            \\<!DOCTYPE html>
            \\<html lang="en" data-theme="dark">
            \\<head>
            \\    <meta charset="UTF-8">
            \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \\    <link rel="icon" type="image/x-icon" href="{{root_path}}favicon.png">
            \\    <title>{{title}}</title>
            \\    <meta name="color-scheme" content="light dark">
            \\    <link rel="stylesheet" href="{{root_path}}ilioCSS.min.css">
            \\    <link rel="stylesheet" href="{{root_path}}style.css">
            \\   
            \\</head>
            \\<body>
            \\    <header class="container">
            \\      <nav>
            \\          <a href="{{root_path}}index.html"><img src="{{root_path}}logo.svg" class="logo" alt="Logo"/></a>
            \\        <ul>
            \\          <li>
            \\            <a href="{{root_path}}posts.html"><button>Posts</button></a>
            \\          </li>
            \\        </ul>
            \\      </nav>
            \\    </header>
            \\    <main class="container">
            \\      <article>
            \\        {{content}}
            \\      </article>
            \\    </main>
            \\    <footer class="container" style="margin: 0.5em 0 0 0;!important">
            \\         <nav>
            \\           <p>&copy 2026 <span><a href="{{root_path}}about.html" data-tooltip="That's me!">ilios</a></p>
            \\           <span style="margin-bottom:1em"><span class="love" data-tooltip="Only pure HTML/CSS">Made</span> <span class="love" data-placement="left" data-tooltip="No Javascript">with</span> <span class="love" data-placement="left" data-tooltip="No tracking"><img src="heart.svg" class="icon" alt="Love"/></span></span>
            \\         </nav>
            \\    </footer>
            \\</body>
            \\</html>
        ;

        return SiteGenerator{
            .allocator = allocator,
            .posts = posts,
            .dir_path = dir_path,
            .template = try allocator.dupe(u8, default_template),
        };
    }

    /// Clean up all allocated memory when the generator is no longer needed
    /// - Frees memory for each post's fields
    /// - Deinitializes the posts ArrayList
    /// - Frees the template string
    pub fn deinit(self: *SiteGenerator) void {
        for (self.posts.items) |post| {
            self.allocator.free(post.title);
            self.allocator.free(post.content);
            self.allocator.free(post.directory);
            self.allocator.free(post.filename);
        }
        self.posts.deinit(self.allocator);
        self.allocator.free(self.template);
    }

    /// Converts markdown text to HTML with support for various markdown features
    /// - Headers (h1, h2, h3)
    /// - Lists (unordered)
    /// - Code blocks (with triple backticks)
    /// - Blockquotes
    /// - Horizontal rules
    /// - Paragraphs
    /// - Inline formatting (bold, italic, code)
    /// - Links and automatic URL detection
    /// - Images
    /// Returns the resulting HTML as an owned slice
    fn convertMarkdownToHtml(self: *SiteGenerator, markdown: []const u8) ![]const u8 {
        var html: ArrayList(u8) = .{};
        errdefer html.deinit(self.allocator);

        var lines = mem.splitSequence(u8, markdown, "\n");
        var in_paragraph = false;
        var in_list = false;
        var in_code_block = false;
        var in_blockquote = false;
        var prev_blank = false;

        while (lines.next()) |line| {
            const trimmed = mem.trim(u8, line, " \t\r\n");

            // Handle empty lines
            if (trimmed.len == 0) {
                if (in_paragraph) {
                    try html.appendSlice(self.allocator, "</p>\n");
                    in_paragraph = false;
                }
                if (in_list) {
                    try html.appendSlice(self.allocator, "</ul>\n");
                    in_list = false;
                }

                // Don't exit blockquote mode on empty lines
                // Just add an empty line to the blockquote
                if (in_blockquote) {
                    try html.appendSlice(self.allocator, "<br>\n");
                }

                // Notice we don't close code blocks on empty lines - they continue until ```
                prev_blank = true;
                continue;
            }

            // Code blocks (triple backticks)
            if (mem.eql(u8, trimmed, "```") or mem.startsWith(u8, trimmed, "``` ")) {
                if (in_code_block) {
                    try html.appendSlice(self.allocator, "</code></pre>\n");
                    in_code_block = false;
                } else {
                    if (in_paragraph) {
                        try html.appendSlice(self.allocator, "</p>\n");
                        in_paragraph = false;
                    }
                    if (in_blockquote) {
                        try html.appendSlice(self.allocator, "</blockquote>\n");
                        in_blockquote = false;
                    }
                    try html.appendSlice(self.allocator, "<pre><code>");
                    in_code_block = true;
                }
                continue;
            }

            if (in_code_block) {
                // Preserve the original line with all whitespace for code blocks
                // Escape HTML special characters in code blocks
                for (line) |char| {
                    switch (char) {
                        '<' => try html.appendSlice(self.allocator, "&lt;"),
                        '>' => try html.appendSlice(self.allocator, "&gt;"),
                        '&' => try html.appendSlice(self.allocator, "&amp;"),
                        else => try html.append(self.allocator, char),
                    }
                }
                try html.appendSlice(self.allocator, "\n");
                continue;
            }

            // Blockquote handling - handle multiline blockquotes
            if (mem.startsWith(u8, trimmed, "> ")) {
                if (in_paragraph) {
                    try html.appendSlice(self.allocator, "</p>\n");
                    in_paragraph = false;
                }

                if (!in_blockquote) {
                    try html.appendSlice(self.allocator, "<blockquote>\n");
                    in_blockquote = true;
                }

                // Handle nested formatting inside the blockquote without adding paragraph tags
                try appendWithFormatting(self.allocator, &html, trimmed[2..]);
                try html.appendSlice(self.allocator, "\n");

                continue;
            } else if (in_blockquote and !mem.startsWith(u8, trimmed, ">")) {
                // Only exit blockquote if this isn't an empty line and doesn't start with ">"
                try html.appendSlice(self.allocator, "</blockquote>\n");
                in_blockquote = false;
            }

            // Headers
            if (mem.startsWith(u8, trimmed, "# ")) {
                if (in_paragraph) {
                    try html.appendSlice(self.allocator, "</p>\n");
                    in_paragraph = false;
                }
                try html.appendSlice(self.allocator, "<h1>");
                try appendWithFormatting(self.allocator, &html, trimmed[2..]);
                try html.appendSlice(self.allocator, "</h1>\n");
            } else if (mem.startsWith(u8, trimmed, "## ")) {
                if (in_paragraph) {
                    try html.appendSlice(self.allocator, "</p>\n");
                    in_paragraph = false;
                }
                try html.appendSlice(self.allocator, "<h2>");
                try appendWithFormatting(self.allocator, &html, trimmed[3..]);
                try html.appendSlice(self.allocator, "</h2>\n");
            } else if (mem.startsWith(u8, trimmed, "### ")) {
                if (in_paragraph) {
                    try html.appendSlice(self.allocator, "</p>\n");
                    in_paragraph = false;
                }
                try html.appendSlice(self.allocator, "<h3>");
                try appendWithFormatting(self.allocator, &html, trimmed[4..]);
                try html.appendSlice(self.allocator, "</h3>\n");
                // Lists
            } else if (mem.startsWith(u8, trimmed, "- ") or mem.startsWith(u8, trimmed, "* ")) {
                if (in_paragraph) {
                    try html.appendSlice(self.allocator, "</p>\n");
                    in_paragraph = false;
                }

                if (!in_list) {
                    try html.appendSlice(self.allocator, "<ul>\n");
                    in_list = true;
                }

                try html.appendSlice(self.allocator, "<li>");
                const list_content = if (mem.startsWith(u8, trimmed, "- ")) trimmed[2..] else trimmed[2..];
                try appendWithFormatting(self.allocator, &html, list_content);
                try html.appendSlice(self.allocator, "</li>\n");
                // Horizontal Rule
            } else if (mem.eql(u8, trimmed, "---") or mem.eql(u8, trimmed, "***") or mem.eql(u8, trimmed, "___")) {
                if (in_paragraph) {
                    try html.appendSlice(self.allocator, "</p>\n");
                    in_paragraph = false;
                }
                try html.appendSlice(self.allocator, "<hr>\n");
                // Paragraphs (default)
            } else {
                if (!in_paragraph) {
                    try html.appendSlice(self.allocator, "<p>");
                    in_paragraph = true;
                } else {
                    try html.appendSlice(self.allocator, " ");
                }
                try appendWithFormatting(self.allocator, &html, trimmed);
            }

            prev_blank = false;
        }

        // Close any open tags
        if (in_paragraph) {
            try html.appendSlice(self.allocator, "</p>\n");
        }
        if (in_list) {
            try html.appendSlice(self.allocator, "</ul>\n");
        }
        if (in_code_block) {
            try html.appendSlice(self.allocator, "</code></pre>\n");
        }
        if (in_blockquote) {
            try html.appendSlice(self.allocator, "</blockquote>\n");
        }

        return html.toOwnedSlice(self.allocator);
    }

    /// Helper function to process inline markdown formatting
    /// Handles:
    /// - Bold (**text** or __text__)
    /// - Italic (*text* or _text_)
    /// - Inline code (`text`)
    /// - Links ([text](url))
    /// - Images (![alt](url))
    /// - Automatic URL detection
    fn appendWithFormatting(allocator: Allocator, html: *ArrayList(u8), text: []const u8) !void {
        var i: usize = 0;
        var in_bold = false;
        var in_italic = false;
        var in_code = false;
        var in_link_text = false;
        var in_link_url = false;
        var in_image_alt = false;
        var in_image_url = false;
        var link_text: ArrayList(u8) = .{};
        defer link_text.deinit(allocator);
        var alt_text: ArrayList(u8) = .{};
        defer alt_text.deinit(allocator);

        while (i < text.len) {
            // Images ![alt](url) - must check for this before links
            if (i + 1 < text.len and text[i] == '!' and text[i + 1] == '[' and !in_link_text and !in_link_url and !in_image_alt and !in_image_url) {
                in_image_alt = true;
                alt_text.clearRetainingCapacity();
                i += 2; // Skip '!['
                continue;
            }

            if (text[i] == ']' and in_image_alt) {
                in_image_alt = false;
                // Check if next chars are '('
                if (i + 1 < text.len and text[i + 1] == '(') {
                    in_image_url = true;
                    i += 2; // Skip ']('
                    try html.appendSlice(allocator, "<img src=\"");
                } else {
                    // Not a proper image, just render the collected text
                    try html.appendSlice(allocator, "![");
                    try html.appendSlice(allocator, alt_text.items);
                    try html.appendSlice(allocator, "]");
                    i += 1;
                }
                continue;
            }

            if (text[i] == ')' and in_image_url) {
                in_image_url = false;
                try html.appendSlice(allocator, "\" alt=\"");
                try html.appendSlice(allocator, alt_text.items);
                try html.appendSlice(allocator, "\">");

                // Debug print to see the generated HTML
                std.debug.print("Generated image HTML: <img src=\"{s}\" alt=\"{s}\">\n", .{ text[i - 1 - alt_text.items.len .. i], alt_text.items });

                i += 1;
                continue;
            }

            // Bold with ** or __
            if (i + 1 < text.len and ((text[i] == '*' and text[i + 1] == '*') or
                (text[i] == '_' and text[i + 1] == '_')))
            {
                if (in_bold) {
                    try html.appendSlice(allocator, "</strong>");
                } else {
                    try html.appendSlice(allocator, "<strong>");
                }
                in_bold = !in_bold;
                i += 2;
                continue;
            }

            // Italic with * or _
            if ((text[i] == '*' or text[i] == '_') and
                (i == 0 or text[i - 1] != text[i]) and
                (i + 1 == text.len or text[i + 1] != text[i]))
            {
                if (in_italic) {
                    try html.appendSlice(allocator, "</em>");
                } else {
                    try html.appendSlice(allocator, "<em>");
                }
                in_italic = !in_italic;
                i += 1;
                continue;
            }

            // Inline code with `
            if (text[i] == '`') {
                if (in_code) {
                    try html.appendSlice(allocator, "</code>");
                } else {
                    try html.appendSlice(allocator, "<code>");
                }
                in_code = !in_code;
                i += 1;
                continue;
            }

            // Links [text](url)
            if (text[i] == '[' and !in_link_text and !in_link_url and !in_image_alt and !in_image_url) {
                in_link_text = true;
                link_text.clearRetainingCapacity();
                i += 1;
                continue;
            }

            if (text[i] == ']' and in_link_text) {
                in_link_text = false;
                // Check if next chars are '('
                if (i + 1 < text.len and text[i + 1] == '(') {
                    in_link_url = true;
                    i += 2; // Skip ']('
                    try html.appendSlice(allocator, "<a href=\"");
                } else {
                    // Not a proper link, just render the collected text
                    try html.appendSlice(allocator, "[");
                    try html.appendSlice(allocator, link_text.items);
                    try html.appendSlice(allocator, "]");
                    i += 1;
                }
                continue;
            }

            if (text[i] == ')' and in_link_url) {
                in_link_url = false;
                try html.appendSlice(allocator, "\">");
                try html.appendSlice(allocator, link_text.items);
                try html.appendSlice(allocator, "</a>");
                i += 1;
                continue;
            }

            // Normal character handling
            if (in_link_text) {
                try link_text.append(allocator, text[i]);
            } else if (in_link_url) {
                try html.append(allocator, text[i]);
            } else if (in_image_alt) {
                try alt_text.append(allocator, text[i]);
            } else if (in_image_url) {
                try html.append(allocator, text[i]);
            } else if (in_code) {
                // Escape HTML special characters in code spans
                switch (text[i]) {
                    '<' => try html.appendSlice(allocator, "&lt;"),
                    '>' => try html.appendSlice(allocator, "&gt;"),
                    '&' => try html.appendSlice(allocator, "&amp;"),
                    else => try html.append(allocator, text[i]),
                }
            } else {
                // Check for automatic links (http://...)
                if (i + 7 < text.len and
                    mem.eql(u8, text[i .. i + 7], "http://") or
                    (i + 8 < text.len and mem.eql(u8, text[i .. i + 8], "https://")))
                {

                    // Find the end of the URL
                    var url_end = i;
                    while (url_end < text.len and !mem.containsAtLeast(u8, " \t\n\r\"'()<>[]", 1, &[_]u8{text[url_end]})) {
                        url_end += 1;
                    }

                    if (url_end > i) {
                        const url = text[i..url_end];
                        try html.appendSlice(allocator, "<a href=\"");
                        try html.appendSlice(allocator, url);
                        try html.appendSlice(allocator, "\">");
                        try html.appendSlice(allocator, url);
                        try html.appendSlice(allocator, "</a>");
                        i = url_end;
                        continue;
                    }
                }

                // Regular character
                try html.append(allocator, text[i]);
            }

            i += 1;
        }

        // Make sure to close any open formatting
        if (in_bold) try html.appendSlice(allocator, "</strong>");
        if (in_italic) try html.appendSlice(allocator, "</em>");
        if (in_code) try html.appendSlice(allocator, "</code>");

        // Handle unclosed link markup
        if (in_link_text) {
            try html.appendSlice(allocator, "[");
            try html.appendSlice(allocator, link_text.items);
        }

        // Handle unclosed image markup
        if (in_image_alt) {
            try html.appendSlice(allocator, "![");
            try html.appendSlice(allocator, alt_text.items);
        }
    }

    /// Extract the post title from the first h1 heading in the markdown
    /// Returns "Untitled Post" if no h1 heading is found
    fn getPostTitle(markdown: []const u8) ![]const u8 {
        var lines = mem.splitSequence(u8, markdown, "\n");
        while (lines.next()) |line| {
            const trimmed = mem.trim(u8, line, " \t\r\n");
            if (mem.startsWith(u8, trimmed, "# ")) {
                return trimmed[2..];
            }
        }
        return "Untitled Post";
    }

    /// Calculate how many directory levels deep a path is
    /// Used to determine the relative path back to the site root
    fn calculatePathDepth(directory: []const u8) usize {
        if (directory.len == 0) return 0;

        var depth: usize = 0;
        for (directory) |char| {
            if (char == '/') depth += 1;
        }

        // If directory doesn't end with '/', add one more level
        if (directory[directory.len - 1] != '/') depth += 1;

        return depth;
    }

    /// Generate a path prefix to reach the site root from a given directory
    /// For example, a page in "posts/tech/" needs "../../" to reach root
    fn generateRootPath(self: *SiteGenerator, directory: []const u8) ![]const u8 {
        const depth = calculatePathDepth(directory);
        if (depth == 0) return self.allocator.dupe(u8, "");

        var path = ArrayList(u8){};
        defer path.deinit(self.allocator);

        var i: usize = 0;
        while (i < depth) : (i += 1) {
            try path.appendSlice(self.allocator, "../");
        }

        return path.toOwnedSlice(self.allocator);
    }

    /// Create a default stylesheet (style.css) if it doesn't exist
    /// Contains basic CSS for site layout and styling
    fn createDefaultStylesheet(self: *SiteGenerator) !void {
        const style_path = try fs.path.join(self.allocator, &[_][]const u8{
            self.dir_path, "style.css",
        });
        defer self.allocator.free(style_path);

        // Always regenerate from hardcoded source
        const default_css =
            \\* {
            \\  /* Dracula Color Palette as CSS Variables */
            \\  --dracula-background: #282a36;
            \\  --dracula-foreground: #f8f8f2;
            \\  --dracula-selection: #44475a;
            \\  --dracula-comment: #6272a4;
            \\  --dracula-cyan: #8be9fd;
            \\  --dracula-green: #50fa7b;
            \\  --dracula-pink: #ff79c6;
            \\  --dracula-purple: #bd93f9;
            \\}
            \\html, body {
            \\  overflow-x: hidden;
            \\}
            \\[data-tooltip] {
            \\  position: relative;
            \\}
            \\[data-tooltip]::after {
            \\  right: auto;
            \\  left: 50%;
            \\  transform: translateX(-50%);
            \\  max-width: 90vw;
            \\  white-space: nowrap;
            \\}
            \\.smooth {
            \\  transition: all 1s ease-in;
            \\}
            \\.logo {
            \\  height:2.5em;
            \\}
            \\.icon {
            \\  height:1em;
            \\  display:inline;
            \\  margin:0;
            \\}
            \\.love {
            \\  text-decoration:none !important;
            \\  border-bottom:none !important;
            \\  cursor:pointer !important;
            \\}
            \\footer > section > nav {
            \\  align-items: center;
            \\  display: flex;
            \\  justify-content: space-between;
            \\}
        ;

        var file = try fs.cwd().createFile(style_path, .{});
        defer file.close();
        _ = try file.writeAll(default_css);
        std.debug.print("Generated style.css\n", .{});
    }

    /// Scan the directory for markdown files and process them
    /// - Walks through all subdirectories recursively
    /// - Reads and parses each .md file
    /// - Extracts title and converts content to HTML
    /// - Stores posts in the posts ArrayList
    pub fn scanDirectory(self: *SiteGenerator) !void {
        var dir = try fs.cwd().openDir(self.dir_path, .{ .iterate = true });
        defer dir.close();

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            const ext = fs.path.extension(entry.basename);
            if (mem.eql(u8, ext, ".md")) {
                var file = try entry.dir.openFile(entry.basename, .{});
                defer file.close();

                const file_size = try file.getEndPos();
                const content = try self.allocator.alloc(u8, file_size);
                defer self.allocator.free(content);
                _ = try file.readAll(content);

                const title = try self.allocator.dupe(u8, try getPostTitle(content));
                const html_content = try self.convertMarkdownToHtml(content);
                const directory = try self.allocator.dupe(u8, entry.path[0 .. entry.path.len - entry.basename.len]);
                const filename = try self.allocator.dupe(u8, entry.basename);

                try self.posts.append(self.allocator, Post{
                    .title = title,
                    .content = html_content,
                    .directory = directory,
                    .filename = filename,
                });
            }
        }
    }

    /// Replace all occurrences of a substring in a string
    /// Creates a new string with all replacements made
    fn replaceAllInString(allocator: Allocator, original: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
        var result = ArrayList(u8){};
        errdefer result.deinit(allocator);

        var parts = mem.splitSequence(u8, original, needle);

        if (parts.next()) |first_part| {
            try result.appendSlice(allocator, first_part);
        }

        while (parts.next()) |part| {
            try result.appendSlice(allocator, replacement);
            try result.appendSlice(allocator, part);
        }

        return result.toOwnedSlice(allocator);
    }

    /// Render a complete HTML page by applying content to the template
    /// - Calculates the correct root path for the page's directory
    /// - Replaces template placeholders with actual content
    /// Returns the complete HTML as a string
    fn renderPage(self: *SiteGenerator, title: []const u8, content: []const u8, directory: []const u8) ![]const u8 {
        // Generate the appropriate root path based on directory depth
        const root_path = try self.generateRootPath(directory);
        defer self.allocator.free(root_path);

        // Start with the template
        var result = try self.allocator.dupe(u8, self.template);
        defer self.allocator.free(result);

        // Replace root_path first
        const temp1 = try replaceAllInString(self.allocator, result, "{{root_path}}", root_path);
        self.allocator.free(result);
        result = temp1;

        // Replace title
        const temp2 = try replaceAllInString(self.allocator, result, "{{title}}", title);
        self.allocator.free(result);
        result = temp2;

        // Replace content
        const temp3 = try replaceAllInString(self.allocator, result, "{{content}}", content);
        self.allocator.free(result);
        result = temp3;

        return self.allocator.dupe(u8, result);
    }

    /// Delete an HTML file if it exists
    /// Used to clean up old files before regenerating
    fn deleteHtmlFile(path: []const u8) !void {
        fs.cwd().deleteFile(path) catch |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        };
    }

    /// Generate a sitemap.xml file for search engine optimization
    /// Lists all pages with their URLs and update frequency
    fn generateSitemapXml(self: *SiteGenerator) ![]const u8 {
        var sitemap_xml = ArrayList(u8){};
        errdefer sitemap_xml.deinit(self.allocator);

        // Get the domain from the first post path to construct absolute URLs
        // This is a simplification - in a real app, we'd want to configure the domain
        const domain = "https://www.ilios.dev"; // Replace with your actual domain

        try sitemap_xml.appendSlice(self.allocator, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        try sitemap_xml.appendSlice(self.allocator, "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n");

        // Add the homepage
        try sitemap_xml.appendSlice(self.allocator, "  <url>\n");
        try sitemap_xml.appendSlice(self.allocator, "    <loc>");
        try sitemap_xml.appendSlice(self.allocator, domain);
        try sitemap_xml.appendSlice(self.allocator, "/index.html</loc>\n");
        try sitemap_xml.appendSlice(self.allocator, "    <changefreq>weekly</changefreq>\n");
        try sitemap_xml.appendSlice(self.allocator, "    <priority>1.0</priority>\n");
        try sitemap_xml.appendSlice(self.allocator, "  </url>\n");

        // Add the posts page
        try sitemap_xml.appendSlice(self.allocator, "  <url>\n");
        try sitemap_xml.appendSlice(self.allocator, "    <loc>");
        try sitemap_xml.appendSlice(self.allocator, domain);
        try sitemap_xml.appendSlice(self.allocator, "/posts.html</loc>\n");
        try sitemap_xml.appendSlice(self.allocator, "    <changefreq>weekly</changefreq>\n");
        try sitemap_xml.appendSlice(self.allocator, "    <priority>0.8</priority>\n");
        try sitemap_xml.appendSlice(self.allocator, "  </url>\n");

        // Add all the posts
        for (self.posts.items) |post| {
            const link_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}{s}.html",
                .{
                    post.directory,
                    post.filename[0 .. post.filename.len - 3],
                },
            );
            defer self.allocator.free(link_path);

            try sitemap_xml.appendSlice(self.allocator, "  <url>\n");
            try sitemap_xml.appendSlice(self.allocator, "    <loc>");
            try sitemap_xml.appendSlice(self.allocator, domain);
            try sitemap_xml.appendSlice(self.allocator, "/");
            try sitemap_xml.appendSlice(self.allocator, link_path);
            try sitemap_xml.appendSlice(self.allocator, "</loc>\n");
            try sitemap_xml.appendSlice(self.allocator, "    <changefreq>monthly</changefreq>\n");
            try sitemap_xml.appendSlice(self.allocator, "    <priority>0.6</priority>\n");
            try sitemap_xml.appendSlice(self.allocator, "  </url>\n");
        }

        try sitemap_xml.appendSlice(self.allocator, "</urlset>");

        return sitemap_xml.toOwnedSlice(self.allocator);
    }

    /// Deletes and recreates stylesheet, index, sitemap, and posts.
    pub fn generateSite(self: *SiteGenerator) !void {
        // Always regenerate stylesheet from hardcoded source
        try self.createDefaultStylesheet();

        // Delete and recreate index and posts files
        const index_path = try fs.path.join(self.allocator, &[_][]const u8{
            self.dir_path, "index.html",
        });
        defer self.allocator.free(index_path);
        try deleteHtmlFile(index_path);

        const posts_path = try fs.path.join(self.allocator, &[_][]const u8{
            self.dir_path, "posts.html",
        });
        defer self.allocator.free(posts_path);
        try deleteHtmlFile(posts_path);

        // Delete old sitemap.html if it exists (for migration)
        const old_sitemap_path = try fs.path.join(self.allocator, &[_][]const u8{
            self.dir_path, "sitemap.html",
        });
        defer self.allocator.free(old_sitemap_path);
        try deleteHtmlFile(old_sitemap_path);

        // Set up the path for sitemap.xml
        const sitemap_xml_path = try fs.path.join(self.allocator, &[_][]const u8{
            self.dir_path, "sitemap.xml",
        });
        defer self.allocator.free(sitemap_xml_path);
        try deleteHtmlFile(sitemap_xml_path);

        // Generate post pages
        for (self.posts.items) |post| {
            const html_filename = try std.fmt.allocPrint(
                self.allocator,
                "{s}.html",
                .{post.filename[0 .. post.filename.len - 3]},
            );
            defer self.allocator.free(html_filename);

            const full_dir_path = try fs.path.join(self.allocator, &[_][]const u8{
                self.dir_path, post.directory,
            });
            defer self.allocator.free(full_dir_path);

            // Create directory if it doesn't exist
            fs.cwd().makeDir(full_dir_path) catch |err| {
                if (err != error.PathAlreadyExists) {
                    return err;
                }
            };

            const output_file_path = try fs.path.join(self.allocator, &[_][]const u8{
                full_dir_path, html_filename,
            });
            defer self.allocator.free(output_file_path);

            // Delete existing HTML file if it exists
            try deleteHtmlFile(output_file_path);

            const rendered_page = try self.renderPage(post.title, post.content, post.directory);
            defer self.allocator.free(rendered_page);

            var file = try fs.cwd().createFile(output_file_path, .{});
            defer file.close();
            _ = try file.writeAll(rendered_page);

            std.debug.print("Generated: {s}\n", .{output_file_path});
        }

        // Generate posts page (formerly sitemap.html)
        var posts_content = ArrayList(u8){};
        defer posts_content.deinit(self.allocator);

        try posts_content.appendSlice(self.allocator, "<h1>Posts</h1>\n<ul>\n");
        for (self.posts.items) |post| {
            const link_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}{s}.html",
                .{
                    post.directory,
                    post.filename[0 .. post.filename.len - 3],
                },
            );
            defer self.allocator.free(link_path);

            try posts_content.appendSlice(self.allocator, "<li><a href=\"");
            try posts_content.appendSlice(self.allocator, link_path);
            try posts_content.appendiSlice(self.allocator, "\">");
            try posts_content.appendSlice(self.allocator, post.title);
            try posts_content.appendSlice(self.allocator, "</a></li>\n");
        }
        try posts_content.appendSlice(self.allocator, "</ul>");

        // For root-level pages, use empty directory
        const empty_dir = "";
        const posts_page = try self.renderPage("Posts", posts_content.items, empty_dir);
        defer self.allocator.free(posts_page);

        var posts_file = try fs.cwd().createFile(posts_path, .{});
        defer posts_file.close();
        _ = try posts_file.writeAll(posts_page);
        std.debug.print("Generated: {s}\n", .{posts_path});

        // Generate landing page
        var landing_content = ArrayList(u8){};
        defer landing_content.deinit(self.allocator);

        try landing_content.appendSlice(self.allocator, "<h1>Welcome</h1>\n");
        try landing_content.appendSlice(self.allocator, "<h3>Browse the latest posts:</h3>\n<ul>\n");

        // Sort posts (assuming newest first, could be improved)
        const recent_posts = if (self.posts.items.len > 5) 5 else self.posts.items.len;
        var i: usize = 0;
        while (i < recent_posts) : (i += 1) {
            const post = self.posts.items[self.posts.items.len - 1 - i];
            const link_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}{s}.html",
                .{
                    post.directory,
                    post.filename[0 .. post.filename.len - 3],
                },
            );
            defer self.allocator.free(link_path);

            try landing_content.appendSlice(self.allocator, "<li><a href=\"");
            try landing_content.appendSlice(self.allocator, link_path);
            try landing_content.appendSlice(self.allocator, "\">");
            try landing_content.appendSlice(self.allocator, post.title);
            try landing_content.appendSlice(self.allocator, "</a></li>\n");
        }

        try landing_content.appendSlice(self.allocator, "</ul>\n");
        try landing_content.appendSlice(self.allocator, "<p><a href=\"posts.html\">View all posts</a></p>");

        const landing_page = try self.renderPage("Home", landing_content.items, empty_dir);
        defer self.allocator.free(landing_page);

        var landing_file = try fs.cwd().createFile(index_path, .{});
        defer landing_file.close();
        _ = try landing_file.writeAll(landing_page);
        std.debug.print("Generated: {s}\n", .{index_path});

        // Generate sitemap.xml for search engines
        const sitemap_xml_content = try self.generateSitemapXml();
        defer self.allocator.free(sitemap_xml_content);

        var sitemap_xml_file = try fs.cwd().createFile(sitemap_xml_path, .{});
        defer sitemap_xml_file.close();
        _ = try sitemap_xml_file.writeAll(sitemap_xml_content);
        std.debug.print("Generated: {s}\n", .{sitemap_xml_path});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <directory>\n", .{args[0]});
        return error.InvalidArguments;
    }

    const dir_path = args[1];

    var site_generator = try SiteGenerator.init(allocator, dir_path);
    defer site_generator.deinit();

    std.debug.print("Scanning directory: {s}\n", .{dir_path});
    try site_generator.scanDirectory();
    std.debug.print("Found {d} posts\n", .{site_generator.posts.items.len});

    std.debug.print("Generating site in the same directory\n", .{});
    try site_generator.generateSite();
    std.debug.print("Site generated successfully!\n", .{});
}
