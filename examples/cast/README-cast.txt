#
# required for these instructions
#   - asciinema (see: https://asciinema.org/a/377532)
#   - glow (see: https://github.com/charmbracelet/glow)
#   - voiski/svg-term-cli:latest (see: https://hub.docker.com/r/voiski/svg-term-cli)
#
# need two shells
#  #1 to run each scene (A, B, and manual) and
#  #2 to issues the "cut", i.e., pkill asciinema 
#
# shell one: 
# scene 1
./scene.sh scir_ptA.script | asciinema rec --stdin p4play_ptA.cast
# shell two: when shell one command is complete
pkill asciinema

# shell one: 
# scene 2
cp -i -a p4play_ptA.cast p4play_ptB.cast
./scene.sh scir_ptB.script | asciinema rec --stdin --append p4play_ptB.cast
# shell two: when shell one command is complete
pkill asciinema

# shell one (no need for two shells for scene 3): 
# scene 3
cp -i -a p4play_ptB.cast p4play_ptB-manual.cast
asciinema rec --stdin --append p4play_ptB-manual.cast
# manually type these next two commands
glow -p oparest/oparest_scir.md
# done
exit

# now make the SVG
cat p4play_ptB-manual.cast | docker run --rm -i voiski/svg-term-cli >> p4play_example.svg

# replace oparest_example.svg with p4play_example.svg
# replace oparest_scir.md with new oparest/oparest_scir.md
#