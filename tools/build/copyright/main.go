/*
Copyright (c) Advanced Micro Devices, Inc. All rights reserved.

Licensed under the Apache License, Version 2.0 (the \"License\");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an \"AS IS\" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

func addCopyright(filePath, yourCopyright string) error {
	// Regular expression to match a copyright notice
	copyrightPattern := "Copyright.*"
	existingAMDCopyrightPattern := "Advanced Micro Devices"
	existingApacheCopyrightPattern := "Apache License"

	// Read the file content
	content, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to read file: %w", err)
	}

	// Check if the file has a .go extension
	if !strings.HasSuffix(filePath, ".go") {
		return nil // Skip non-Go files
	}

	// Find the existing pattern
	match := regexp.MustCompile(copyrightPattern).FindIndex(content)
	packageMatch := regexp.MustCompile("package").FindIndex(content)

	if match == nil {
		// If no existing copyright is found, add the new one at the beginning
		newContent := append([]byte(yourCopyright+"\n\n"), content...)
		err = os.WriteFile(filePath, newContent, os.ModeAppend)
		if err != nil {
			return fmt.Errorf("failed to write file: %w", err)
		}
		fmt.Printf("Copyright notice added to %s (no existing copyright found)\n", filePath)
		return nil
	}

	// Check if the existing copyright matches the skip pattern
	foundExisting := false
	foundExistingAMD := false
	if strings.Contains(string(content[:packageMatch[0]]), existingAMDCopyrightPattern) &&
		strings.Contains(string(content[:packageMatch[0]]), existingApacheCopyrightPattern) {
		foundExistingAMD = true
	} else if strings.Contains(string(content[:packageMatch[0]]), "Copyright") {
		foundExisting = true
	}

	switch {
	case foundExistingAMD:
		fmt.Printf("Skipping %s: Existing copyright matches pattern\n", filePath)
		return nil
	case foundExisting:
		// // Add the new copyright after the existing one
		existingCopyright := content[:packageMatch[0]]
		newContent := append([]byte(string(existingCopyright)+"\n"), []byte(yourCopyright+"\n\n")...)
		newContent = append(newContent, content[packageMatch[0]:]...)
		err = os.WriteFile(filePath, newContent, os.ModeAppend)
		if err != nil {
			return fmt.Errorf("failed to write file: %w", err)
		}
		fmt.Printf("Copyright notice appended in %s\n", filePath)
		return nil
	default:
		// Replace the existing copyright with the new one
		newContent := append([]byte(yourCopyright+"\n\n"), content[packageMatch[0]:]...)
		err = os.WriteFile(filePath, newContent, os.ModeAppend)
		if err != nil {
			return fmt.Errorf("failed to write file: %w", err)
		}
		fmt.Printf("Copyright notice added in %s\n", filePath)
	}

	return nil
}

func main() {
	// Cutoff date: May 6th, 2025
	cutoff := time.Date(2025, 5, 6, 0, 0, 0, 0, time.UTC)

	yourCopyright := `
/*
Copyright (c) Advanced Micro Devices, Inc. All rights reserved.

Licensed under the Apache License, Version 2.0 (the \"License\");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an \"AS IS\" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/`
	directoryPath := "./"
	skipDirectory := "vendor" // Replace with the directory name to skip

	// Iterate through all files in the directory
	err := filepath.Walk(directoryPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if info.IsDir() {
			if info.Name() == skipDirectory {
				fmt.Printf("Skipping directory: %s\n", skipDirectory)
				return filepath.SkipDir // Skip the directory and its subdirectories
			}
			return nil
		}

		// Check if the file has a .go extension
		if !strings.HasSuffix(info.Name(), ".go") {
			return nil // Skip non-Go files
		}

		// Only process files created or updated after cutoff date
		eligible, err := isFileModifiedAfter(path, cutoff)
		if err != nil {
			fmt.Printf("Skipping %s due to git error: %v\n", path, err)
			return nil
		}

		if !eligible {
			fmt.Printf("Skipping %s: created/updated before repo creation\n", path)
			return nil
		}

		err = addCopyright(path, yourCopyright)
		return err
	})

	if err != nil {
		fmt.Println("Error:", err)
	}
}

// isFileModifiedAfter returns true if the file was created or updated after the given time
func isFileModifiedAfter(filePath string, after time.Time) (bool, error) {
	cmd := exec.Command("git", "log", "-1", "--format=%ct", "--", filePath)
	out, err := cmd.Output()
	if err != nil {
		// If the file is not tracked yet, treat as new → eligible
		return true, nil
	}

	tsStr := strings.TrimSpace(string(out))
	if tsStr == "" {
		// Untracked file → treat as new
		return true, nil
	}

	ts, err := strconv.ParseInt(tsStr, 10, 64)
	if err != nil {
		return false, fmt.Errorf("failed to parse file commit timestamp: %w", err)
	}

	lastModified := time.Unix(ts, 0)
	return lastModified.After(after), nil
}
